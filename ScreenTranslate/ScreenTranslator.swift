import Foundation
import ImageIO

struct RenderedTranslation {
    /// The screenshot with translation panels, as PNG.
    let png: Data
    let regions: [TranslatedRegion]
    let source: SourceLanguage
}

/// Everything the user can choose that affects a translation.
struct TranslationSettings {
    var source: SourceLanguage
    var target: TargetLanguage
    var overlay: OverlayOptions
    /// Nil = don't convert prices.
    var prices: PriceOptions?
    var flagListingTerms: Bool

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
    case languagesNotDownloaded(SourceLanguage, TargetLanguage)
    case languagesUnsupported(SourceLanguage, TargetLanguage)
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
}

/// The whole pipeline: read the text, group it into paragraphs, translate, add price and
/// listing notes, draw the panels. Used by both the Shortcuts action and the in-app test.
enum ScreenTranslator {
    static func translate(_ data: Data, settings: TranslationSettings) async throws -> RenderedTranslation {
        guard let image = loadImage(data) else { throw ScreenTranslateError.unreadableImage }
        let size = CGSize(width: image.width, height: image.height)
        let source = settings.source

        // Keep lines in the source script, plus price-only lines like "¥12,800" when converting.
        let lines = try TextRecognizer.recognizeLines(in: image, language: source).filter { line in
            guard !TextGeometry.isInStatusBar(line.rect, imageSize: size) else { return false }
            return source.matchesScript(line.text)
                || (settings.prices != nil && !PriceParser.prices(in: line.text, language: source).isEmpty)
        }
        let blocks = TextGeometry.groupIntoBlocks(lines)

        // Nothing to translate: hand back the original so the shortcut still shows something.
        guard !blocks.isEmpty else {
            guard let png = OverlayRenderer.render(image: image, regions: [], options: settings.overlay) else {
                throw ScreenTranslateError.renderFailed
            }
            return RenderedTranslation(png: png, regions: [], source: source)
        }

        let originals = blocks.map { $0.text(joinedBy: source.lineJoiner) }
        let translations = try await translateScriptBlocks(originals, settings: settings)
        let rate = await priceRate(settings)

        let regions = blocks.indices.map { index in
            let original = originals[index]
            var notes: [String] = []
            var isWarning = false
            if let prices = settings.prices, let rate {
                notes += PriceParser.prices(in: original, language: source).map {
                    priceNote($0, rate: rate, options: prices)
                }
            }
            if settings.flagListingTerms, source == .japanese {
                for match in ListingTerms.matches(in: original) {
                    notes.append("\(match.isWarning ? "⚠︎ " : "✓ ")\(match.word): \(match.meaning)")
                    isWarning = isWarning || match.isWarning
                }
            }
            return TranslatedRegion(
                original: original,
                translated: translations[index],
                rect: blocks[index].rect,
                notes: notes,
                isWarning: isWarning
            )
        }

        guard let png = OverlayRenderer.render(image: image, regions: regions, options: settings.overlay) else {
            throw ScreenTranslateError.renderFailed
        }
        return RenderedTranslation(png: png, regions: regions, source: source)
    }

    /// Translates the blocks that contain source-language text. Price-only blocks keep their text.
    private static func translateScriptBlocks(_ originals: [String], settings: TranslationSettings) async throws -> [String] {
        let toTranslate = originals.indices.filter { settings.source.matchesScript(originals[$0]) }
        guard !toTranslate.isEmpty else { return originals }

        switch await Translator.status(from: settings.source, to: settings.target) {
        case .installed: break
        case .needsDownload: throw ScreenTranslateError.languagesNotDownloaded(settings.source, settings.target)
        case .unsupported: throw ScreenTranslateError.languagesUnsupported(settings.source, settings.target)
        }

        let translated: [String]
        do {
            translated = try await Translator.translate(toTranslate.map { originals[$0] }, from: settings.source, to: settings.target)
        } catch {
            throw ScreenTranslateError.translationFailed(error.localizedDescription)
        }

        var results = originals
        for (position, index) in toTranslate.enumerated() {
            results[index] = translated[position]
        }
        return results
    }

    private static func priceRate(_ settings: TranslationSettings) async -> Double? {
        guard let prices = settings.prices else { return nil }
        return await ExchangeRates.rate(from: settings.source.homeCurrency, to: prices.currency.rawValue)
    }

    /// "≈ $86.40" or, with extra costs set, "≈ $86.40 · $92.10 with fees".
    private static func priceNote(_ amount: Double, rate: Double, options: PriceOptions) -> String {
        let converted = options.currency.format(amount * rate)
        guard options.extraCost > 0 else { return "≈ \(converted)" }
        let withFees = options.currency.format((amount + options.extraCost) * rate)
        return "≈ \(converted) · \(withFees) with fees"
    }

    /// Decodes the image with its orientation applied. Very tall images (long web page captures)
    /// are scaled down so they fit in memory.
    private static func loadImage(_ data: Data) -> CGImage? {
        guard let source = CGImageSourceCreateWithData(data as CFData, nil) else { return nil }
        let options: [CFString: Any] = [
            kCGImageSourceCreateThumbnailFromImageAlways: true,
            kCGImageSourceCreateThumbnailWithTransform: true,
            kCGImageSourceThumbnailMaxPixelSize: 8000,
        ]
        return CGImageSourceCreateThumbnailAtIndex(source, 0, options as CFDictionary)
    }
}
