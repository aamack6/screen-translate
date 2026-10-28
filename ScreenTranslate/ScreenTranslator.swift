import Foundation
import ImageIO

struct RenderedTranslation {
    /// The image with translation panels, as JPEG.
    let jpeg: Data
    let regions: [TranslatedRegion]
    let target: AppLanguage
    /// How long each step took, like "Read 0.8s · Translate 1.2s · Draw 0.2s".
    let timings: String
}

/// Everything the user can choose that affects a translation.
struct TranslationSettings {
    /// Nil = detect the language automatically.
    var source: AppLanguage?
    var target: AppLanguage
    var overlay: OverlayOptions
    /// Nil = don't convert prices.
    var prices: PriceOptions?
    var flagListingTerms: Bool
    /// Ignore the clock and icons at the top of a screenshot. Off for camera photos.
    var skipStatusBar = true
    /// Count this translation against the free daily allowance.
    var countsTowardAllowance = true

    static var current: TranslationSettings {
        TranslationSettings(
            source: AppSettings.sourceLanguage,
            target: AppSettings.targetLanguage,
            overlay: AppSettings.overlayOptions,
            prices: AppSettings.priceOptions,
            flagListingTerms: AppSettings.flagListingTerms
        )
    }
}

enum ScreenTranslateError: LocalizedError {
    case unreadableImage
    case languagesNotDownloaded(AppLanguage, AppLanguage)
    case languagesUnsupported(AppLanguage, AppLanguage)
    case renderFailed
    case translationFailed(String)

    var errorDescription: String? {
        switch self {
        case .unreadableImage:
            return "The input isn't a readable image. In Shortcuts, connect Take Screenshot to the Screenshot field of Translate Screenshot."
        case .languagesNotDownloaded(let source, let target):
            return "\(source.displayName) to \(target.displayName) isn't downloaded yet. Open ScreenTranslate and tap Download languages."
        case .languagesUnsupported(let source, let target):
            return "\(source.displayName) to \(target.displayName) isn't available on this device. Check that iOS is up to date."
        case .renderFailed:
            return "The translated image couldn't be created. Try a regular screenshot rather than a very long image."
        case .translationFailed(let details):
            return "Translation failed. Open ScreenTranslate, download the languages again, and retry. Details: \(details)"
        }
    }

    /// The language pair the user needs to download, if that's what went wrong.
    var missingPair: (AppLanguage, AppLanguage)? {
        if case let .languagesNotDownloaded(source, target) = self { return (source, target) }
        return nil
    }
}

/// The whole pipeline: read the text, work out which parts need translating and from which
/// language, translate, add price and listing notes, draw the panels. Used by the Shortcuts
/// action and by the app's own photo and camera translation.
enum ScreenTranslator {
    static func translate(_ data: Data, settings: TranslationSettings) async throws -> RenderedTranslation {
        if settings.countsTowardAllowance {
            try await Usage.checkAllowance()
        }
        let clock = ContinuousClock()
        var steps: [String] = []
        var stepStart = clock.now
        func finishStep(_ name: String) {
            let elapsed = (clock.now - stepStart).components
            let seconds = Double(elapsed.seconds) + Double(elapsed.attoseconds) / 1e18
            steps.append("\(name) \(String(format: "%.1f", seconds))s")
            stepStart = clock.now
        }

        // Loading a translation model takes about as long as reading the text, so start it now
        // for the language this screenshot is most likely in.
        let likelySource = settings.source ?? AppSettings.lastDetectedSource
        let warmUp = Task {
            if let likelySource { await Translator.warmUp(from: likelySource, to: settings.target) }
        }

        guard let image = loadImage(data) else { throw ScreenTranslateError.unreadableImage }
        let size = CGSize(width: image.width, height: image.height)

        // Keep lines that need translating, plus price-only lines like "$12.99" when converting.
        var lines: [TextLine] = []
        for var line in try TextRecognizer.recognizeLines(in: image, language: settings.source) {
            if settings.skipStatusBar, TextGeometry.isInStatusBar(line.rect, imageSize: size) { continue }
            line.language = LanguageDetector.sourceLanguage(of: line.text, source: settings.source, target: settings.target)
            let hasForeignPrice = settings.prices.map { options in
                PriceParser.prices(in: line.text, language: settings.source).contains { $0.currency != options.currency }
            } ?? false
            if line.language != nil || hasForeignPrice {
                lines.append(line)
            }
        }
        let blocks = TextGeometry.groupIntoBlocks(lines)
        finishStep("Read")

        let originals = blocks.map(\.text)
        if settings.source == nil {
            let counts = Dictionary(grouping: blocks.compactMap(\.language), by: { $0 }).mapValues(\.count)
            if let mostCommon = counts.max(by: { $0.value < $1.value })?.key {
                AppSettings.lastDetectedSource = mostCommon
            }
        }
        // The real translation reuses the warmed-up session; don't run both at once.
        await warmUp.value
        let translations = try await translateBlocks(blocks, originals: originals, target: settings.target)
        finishStep("Translate")
        let rates = await priceRates(for: originals, blocks: blocks, settings: settings)
        if settings.prices != nil { finishStep("Prices") }

        let regions = blocks.indices.map { index in
            let original = originals[index]
            let language = blocks[index].language ?? settings.source
            var notes: [String] = []
            var isWarning = false
            if let options = settings.prices {
                for price in PriceParser.prices(in: original, language: language) where price.currency != options.currency {
                    if let rate = rates[price.currency] {
                        notes.append(priceNote(price.amount * rate, options: options))
                    }
                }
            }
            if settings.flagListingTerms, language == .japanese {
                for match in ListingTerms.matches(in: original) {
                    notes.append("\(match.isWarning ? "⚠︎ " : "✓ ")\(match.word): \(match.meaning)")
                    isWarning = isWarning || match.isWarning
                }
            }
            return TranslatedRegion(
                original: original,
                translated: translations[index],
                source: blocks[index].language,
                rect: blocks[index].rect,
                notes: notes,
                isWarning: isWarning
            )
        }

        guard let jpeg = OverlayRenderer.render(image: image, regions: regions, options: settings.overlay) else {
            throw ScreenTranslateError.renderFailed
        }
        finishStep("Draw")
        if settings.countsTowardAllowance, regions.contains(where: { $0.source != nil }) {
            Usage.recordTranslation()
        }
        return RenderedTranslation(jpeg: jpeg, regions: regions, target: settings.target, timings: steps.joined(separator: " · "))
    }

    /// Translates each block from its own language, one batch per language. Price-only blocks
    /// keep their text.
    private static func translateBlocks(_ blocks: [TextBlock], originals: [String], target: AppLanguage) async throws -> [String] {
        var results = originals
        let byLanguage = Dictionary(grouping: blocks.indices.filter { blocks[$0].language != nil }) { blocks[$0].language! }

        for (source, indices) in byLanguage.sorted(by: { $0.value.count > $1.value.count }) {
            switch await Translator.status(from: source, to: target) {
            case .installed: break
            case .needsDownload: throw ScreenTranslateError.languagesNotDownloaded(source, target)
            case .unsupported: continue // Leave text Apple can't translate as it is.
            }
            do {
                let translated = try await Translator.translate(indices.map { originals[$0] }, from: source, to: target)
                for (position, index) in indices.enumerated() {
                    results[index] = translated[position]
                }
            } catch {
                throw ScreenTranslateError.translationFailed(error.localizedDescription)
            }
        }
        return results
    }

    /// One exchange rate per currency found on screen.
    private static func priceRates(for originals: [String], blocks: [TextBlock], settings: TranslationSettings) async -> [String: Double] {
        guard let options = settings.prices else { return [:] }
        let currencies = Set(originals.indices.flatMap { index in
            PriceParser.prices(in: originals[index], language: blocks[index].language ?? settings.source).map(\.currency)
        })
        var rates: [String: Double] = [:]
        for currency in currencies where currency != options.currency {
            rates[currency] = await ExchangeRates.rate(from: currency, to: options.currency)
        }
        return rates
    }

    /// "≈ $86.40" or, with extra costs set, "≈ $86.40 · $92.40 with fees".
    private static func priceNote(_ converted: Double, options: PriceOptions) -> String {
        let text = "≈ \(DisplayCurrency.format(converted, code: options.currency))"
        guard options.extraCost > 0 else { return text }
        return "\(text) · \(DisplayCurrency.format(converted + options.extraCost, code: options.currency)) with fees"
    }

    /// Decodes the image with its orientation applied. Very large images (long web page captures,
    /// 48 MP photos) are scaled down so they fit in memory.
    private static func loadImage(_ data: Data) -> CGImage? {
        guard let source = CGImageSourceCreateWithData(data as CFData, nil) else { return nil }
        let options: [CFString: Any] = [
            kCGImageSourceCreateThumbnailFromImageAlways: true,
            kCGImageSourceCreateThumbnailWithTransform: true,
            kCGImageSourceThumbnailMaxPixelSize: 6000,
        ]
        return CGImageSourceCreateThumbnailAtIndex(source, 0, options as CFDictionary)
    }
}
