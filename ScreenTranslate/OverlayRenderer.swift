import UIKit

struct TranslatedRegion: Codable {
    let original: String
    let translated: String
    /// The language this text was translated from; nil for untranslated text (prices only).
    var source: AppLanguage?
    let rect: CGRect
    /// Extra lines under the translation: converted prices and listing-term explanations.
    var notes: [String] = []
    /// True when a note warns about the item's condition; the panel gets an orange border.
    var isWarning = false
    /// Height of the original's tallest line, so the translation can match its size.
    var lineHeight: CGFloat?
    /// The text recognizer wasn't sure it read the original correctly, so the translation may be
    /// wrong too. Shown with a "?" and a dashed border rather than as a confident translation.
    /// Optional so history saved before it existed still loads.
    var uncertain: Bool?

    var isUncertain: Bool { uncertain == true }

    /// Vision's accurate mode rates clear text 1.0 and doubtful readings 0.3 to 0.5. Below this
    /// counts as unsure. To be tuned with real screenshots.
    static let uncertainBelow: Float = 0.5
}

/// Draws translation panels over the original text. Translations too long for their panel get a
/// number, and the full text is listed in a strip added under the screenshot.
enum OverlayRenderer {
    /// - Parameter obstacles: every piece of text on the image, translated or not, so panels don't
    ///   grow over text that's left as it is.
    /// - Parameter summary: lines of a buying summary, listed under the screenshot.
    static func render(image: CGImage, regions: [TranslatedRegion], obstacles: [CGRect], options: OverlayOptions, summary: [String] = []) -> Data? {
        let width = CGFloat(image.width)
        let height = CGFloat(image.height)
        let minFontSize = max(width * 0.026, 10)
        let maxFontSize = width * 0.055
        let colors = Colors(dark: options.darkPanels)

        // Lay out every panel first, so we know which translations need a footnote.
        var panels: [Panel] = []
        var footnotes: [(number: Int, region: TranslatedRegion)] = []
        for region in regions {
            var panel = layoutPanel(for: region, avoiding: regions.map(\.rect) + obstacles, minFontSize: minFontSize, maxFontSize: maxFontSize, imageSize: CGSize(width: width, height: height))
            if !panel.fits || options.appendFullText {
                let number = footnotes.count + 1
                footnotes.append((number, region))
                if !panel.fits {
                    panel.number = number
                }
            }
            panels.append(panel)
        }

        let footer = footerText(footnotes, summary: summary, fontSize: minFontSize * 1.1, colors: colors)
        let footerPadding = minFontSize
        let footerHeight = footnotes.isEmpty && summary.isEmpty ? 0 : ceil(measure(footer, width: width - footerPadding * 2).height) + footerPadding * 2

        let format = UIGraphicsImageRendererFormat()
        format.scale = 1
        format.opaque = true
        let renderer = UIGraphicsImageRenderer(size: CGSize(width: width, height: height + footerHeight), format: format)

        return renderer.jpegData(withCompressionQuality: 0.9) { context in
            UIImage(cgImage: image).draw(in: CGRect(x: 0, y: 0, width: width, height: height))

            for panel in panels {
                let path = UIBezierPath(roundedRect: panel.frame, cornerRadius: min(panel.frame.height * 0.2, minFontSize * 0.6))
                colors.panel.setFill()
                path.fill()
                if panel.region.isWarning {
                    colors.warning.setStroke()
                    path.lineWidth = max(minFontSize * 0.15, 2)
                    path.stroke()
                } else if panel.region.isUncertain {
                    colors.uncertain.setStroke()
                    path.lineWidth = max(minFontSize * 0.12, 1.5)
                    path.setLineDash([minFontSize * 0.4, minFontSize * 0.25], count: 2, phase: 0)
                    path.stroke()
                }
                let text = panelText(panel.region, size: panel.fontSize, colors: colors, number: panel.number)
                text.draw(
                    with: panel.frame.insetBy(dx: panel.padding, dy: panel.padding * 0.5),
                    options: [.usesLineFragmentOrigin, .truncatesLastVisibleLine],
                    context: nil
                )
            }

            if footerHeight > 0 {
                colors.footer.setFill()
                context.fill(CGRect(x: 0, y: height, width: width, height: footerHeight))
                footer.draw(
                    with: CGRect(x: footerPadding, y: height + footerPadding, width: width - footerPadding * 2, height: footerHeight),
                    options: [.usesLineFragmentOrigin],
                    context: nil
                )
            }
        }
    }

    // MARK: - Layout

    private struct Panel {
        var frame: CGRect
        var region: TranslatedRegion
        var fontSize: CGFloat
        var padding: CGFloat
        var fits: Bool
        var number: Int?
    }

    /// Picks the largest font that fits the translation in the original text's box. The panel may
    /// grow downward a little, because English usually needs more room than Japanese, but never
    /// into the next text below it. Narrow panels (buttons) widen so no word is split.
    private static func layoutPanel(for region: TranslatedRegion, avoiding others: [CGRect], minFontSize: CGFloat, maxFontSize: CGFloat, imageSize: CGSize) -> Panel {
        let padding = max(region.rect.height * 0.12, minFontSize * 0.3)
        let base = region.rect.insetBy(dx: -padding, dy: -padding * 0.5)
        let own = region.rect.insetBy(dx: -1, dy: -1)
        let nextBelow = others
            .filter { !own.contains($0) && $0.minY > region.rect.maxY - region.rect.height * 0.25 && $0.minX < region.rect.maxX && $0.maxX > region.rect.minX }
            .map(\.minY)
            .min() ?? imageSize.height
        let maxHeight = max(base.height, min(base.height * 1.8, nextBelow - base.minY - padding * 0.25))

        var size = min(maxFontSize, max((region.lineHeight ?? region.rect.height) * 0.85, minFontSize))
        while size >= minFontSize {
            let frame = widened(base, toFit: longestWordWidth(region.translated, size: size) + padding * 2, imageWidth: imageSize.width)
            let needed = measure(panelText(region, size: size, colors: Colors(dark: false), number: nil), width: frame.width - padding * 2).height + padding
            if needed <= maxHeight {
                var fitted = frame
                fitted.size.height = max(base.height, ceil(needed))
                return Panel(frame: fitted, region: region, fontSize: size, padding: padding, fits: true)
            }
            size *= 0.9
        }

        var frame = widened(base, toFit: longestWordWidth(region.translated, size: minFontSize) + padding * 2, imageWidth: imageSize.width)
        frame.size.height = maxHeight
        return Panel(frame: frame, region: region, fontSize: minFontSize, padding: padding, fits: false)
    }

    /// Grows the frame sideways around its center to at least `width`, staying inside the image.
    private static func widened(_ frame: CGRect, toFit width: CGFloat, imageWidth: CGFloat) -> CGRect {
        guard width > frame.width else { return frame }
        var result = frame.insetBy(dx: -(min(width, imageWidth) - frame.width) / 2, dy: 0)
        result.origin.x = min(max(result.minX, 0), imageWidth - result.width)
        return result
    }

    private static func longestWordWidth(_ text: String, size: CGFloat) -> CGFloat {
        let font = UIFont.systemFont(ofSize: size, weight: .medium)
        return text.split(whereSeparator: \.isWhitespace)
            .map { ceil((String($0) as NSString).size(withAttributes: [.font: font]).width) }
            .max() ?? 0
    }

    // MARK: - Text

    private struct Colors {
        let panel: UIColor
        let text: UIColor
        let footer: UIColor
        let note: UIColor
        let warning: UIColor
        let uncertain: UIColor

        init(dark: Bool) {
            panel = dark ? UIColor(white: 0.08, alpha: 0.9) : UIColor(white: 1, alpha: 0.94)
            text = dark ? .white : .black
            footer = dark ? UIColor(white: 0.08, alpha: 1) : .white
            note = dark ? UIColor(red: 0.45, green: 0.85, blue: 0.55, alpha: 1) : UIColor(red: 0.0, green: 0.45, blue: 0.2, alpha: 1)
            warning = dark ? UIColor(red: 1.0, green: 0.62, blue: 0.2, alpha: 1) : UIColor(red: 0.85, green: 0.35, blue: 0.0, alpha: 1)
            uncertain = dark ? UIColor(white: 0.7, alpha: 1) : UIColor(white: 0.4, alpha: 1)
        }
    }

    private static func attributed(_ string: String, size: CGFloat, color: UIColor) -> NSAttributedString {
        let paragraph = NSMutableParagraphStyle()
        paragraph.lineBreakMode = .byWordWrapping
        return NSAttributedString(string: string, attributes: [
            .font: UIFont.systemFont(ofSize: size, weight: .medium),
            .foregroundColor: color,
            .paragraphStyle: paragraph,
        ])
    }

    /// The translation, then each note on its own line in a smaller size: warnings in orange,
    /// prices and good-news terms in green.
    private static func panelText(_ region: TranslatedRegion, size: CGFloat, colors: Colors, number: Int?) -> NSAttributedString {
        let prefix = (number.map { "[\($0)] " } ?? "") + (region.isUncertain ? "(?) " : "")
        let text = NSMutableAttributedString(attributedString: attributed(prefix + region.translated, size: size, color: colors.text))
        for note in region.notes {
            let color = note.hasPrefix("⚠") ? colors.warning : colors.note
            text.append(attributed("\n" + note, size: size * 0.8, color: color))
        }
        return text
    }

    private static func footerText(_ notes: [(number: Int, region: TranslatedRegion)], summary: [String], fontSize: CGFloat, colors: Colors) -> NSAttributedString {
        let text = NSMutableAttributedString()
        if !summary.isEmpty {
            text.append(NSAttributedString(string: "Buying summary, from the seller's wording", attributes: [
                .font: UIFont.systemFont(ofSize: fontSize, weight: .bold),
                .foregroundColor: colors.text,
            ]))
            for line in summary {
                text.append(attributed("\n" + line, size: fontSize * 0.9, color: line.contains("⚠") ? colors.warning : colors.text))
            }
        }
        for (offset, note) in notes.enumerated() {
            if offset > 0 || !summary.isEmpty { text.append(attributed("\n\n", size: fontSize, color: colors.text)) }
            text.append(panelText(note.region, size: fontSize, colors: colors, number: note.number))
        }
        return text
    }

    private static func measure(_ text: NSAttributedString, width: CGFloat) -> CGRect {
        text.boundingRect(
            with: CGSize(width: max(width, 1), height: .greatestFiniteMagnitude),
            options: [.usesLineFragmentOrigin],
            context: nil
        )
    }
}
