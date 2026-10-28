import Foundation
import ImageIO

struct RenderedTranslation {
    /// The screenshot with English panels, as PNG.
    let png: Data
    let regions: [TranslatedRegion]
    let source: SourceLanguage
}

enum ScreenTranslateError: LocalizedError {
    case unreadableImage
    case languagesNotDownloaded(SourceLanguage)
    case languagesUnsupported(SourceLanguage)
    case renderFailed
    case translationFailed(String)

    var errorDescription: String? {
        switch self {
        case .unreadableImage:
            return "The input isn't a readable image. In Shortcuts, connect Take Screenshot to the Screenshot field of Translate Screenshot."
        case .languagesNotDownloaded(let language):
            return "\(language.displayName) to English isn't downloaded yet. Open ScreenTranslate and tap Download languages."
        case .languagesUnsupported(let language):
            return "\(language.displayName) to English isn't available on this device. Check that iOS is up to date."
        case .renderFailed:
            return "The translated image couldn't be created. Try a regular screenshot rather than a very long image."
        case .translationFailed(let details):
            return "Translation failed. Open ScreenTranslate, download the languages again, and retry. Details: \(details)"
        }
    }
}

/// The whole pipeline: read the text, group it into paragraphs, translate, draw the panels.
/// Used by both the Shortcuts action and the in-app test.
enum ScreenTranslator {
    static func translate(_ data: Data, source: SourceLanguage, options: OverlayOptions) async throws -> RenderedTranslation {
        guard let image = loadImage(data) else { throw ScreenTranslateError.unreadableImage }
        let size = CGSize(width: image.width, height: image.height)

        let lines = try TextRecognizer.recognizeLines(in: image, language: source).filter {
            source.matchesScript($0.text) && !TextGeometry.isInStatusBar($0.rect, imageSize: size)
        }
        let blocks = TextGeometry.groupIntoBlocks(lines)

        // Nothing to translate: hand back the original so the shortcut still shows something.
        guard !blocks.isEmpty else {
            guard let png = OverlayRenderer.render(image: image, regions: [], options: options) else {
                throw ScreenTranslateError.renderFailed
            }
            return RenderedTranslation(png: png, regions: [], source: source)
        }

        switch await Translator.status(for: source) {
        case .installed: break
        case .needsDownload: throw ScreenTranslateError.languagesNotDownloaded(source)
        case .unsupported: throw ScreenTranslateError.languagesUnsupported(source)
        }

        let originals = blocks.map { $0.text(joinedBy: source.lineJoiner) }
        let translations: [String]
        do {
            translations = try await Translator.translate(originals, from: source)
        } catch {
            throw ScreenTranslateError.translationFailed(error.localizedDescription)
        }

        let regions = zip(blocks, zip(originals, translations)).map { block, pair in
            TranslatedRegion(original: pair.0, translated: pair.1, rect: block.rect)
        }
        guard let png = OverlayRenderer.render(image: image, regions: regions, options: options) else {
            throw ScreenTranslateError.renderFailed
        }
        return RenderedTranslation(png: png, regions: regions, source: source)
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
