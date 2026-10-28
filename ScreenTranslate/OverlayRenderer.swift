import UIKit

struct TranslatedRegion: Codable {
    let original: String
    let translated: String
    let rect: CGRect
    /// Extra lines under the translation: converted prices and listing-term explanations.
    var notes: [String] = []
    /// True when a note warns about the item's condition; the panel gets an orange border.
    var isWarning = false
}

/// Draws translation panels over the original text. Translations too long for their panel get a
/// number, and the full text is listed in a strip added under the screenshot.
enum OverlayRenderer {
    static func render(image: CGImage, regions: [TranslatedRegion], options: OverlayOptions) -> Data? {
        let width = CGFloat(image.width)
        let height = CGFloat(image.height)
        let minFontSize = max(width * 0.026, 10)
        let maxFontSize = width * 0.055
        let colors = Colors(dark: options.darkPanels)

        // Lay out every panel first, so we know which translations need a footnote.
        var panels: [Panel] = []
        var footnotes: [(number: Int, region: TranslatedRegion)] = []
        for region in regions {
            var panel = layoutPanel(for: region, minFontSize: minFontSize, maxFontSize: maxFontSize, imageHeight: height)
            if !panel.fits || options.appendFullText {
                let number = footnotes.count + 1
                footnotes.append((number, region))
                if !panel.fits {
                    panel.number = number
                }
            }
            panels.append(panel)
        }

        let footer = footerText(footnotes, fontSize: minFontSize * 1.1, colors: colors)
        let footerPadding = minFontSize
        let footerHeight = footnotes.isEmpty ? 0 : ceil(measure(footer, width: width - footerPadding * 2).height) + footerPadding * 2

        let format = UIGraphicsImageRendererFormat()
        format.scale = 1
        format.opaque = true
        let renderer = UIGraphicsImageRenderer(size: CGSize(width: width, height: height + footerHeight), format: format)

        return renderer.pngData { context in
            UIImage(cgImage: image).draw(in: CGRect(x: 0, y: 0, width: width, height: height))

            for panel in panels {
                let path = UIBezierPath(roundedRect: panel.frame, cornerRadius: min(panel.frame.height * 0.2, minFontSize * 0.6))
                colors.panel.setFill()
                path.fill()
                if panel.region.isWarning {
                    colors.warning.setStroke()
                    path.lineWidth = max(minFontSize * 0.15, 2)
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
    /// grow downward a little, because English usually needs more room than Japanese.
    private static func layoutPanel(for region: TranslatedRegion, minFontSize: CGFloat, maxFontSize: CGFloat, imageHeight: CGFloat) -> Panel {
        let padding = max(region.rect.height * 0.12, minFontSize * 0.3)
        let base = region.rect.insetBy(dx: -padding, dy: -padding * 0.5)
        let maxHeight = min(base.height * 1.8, imageHeight - base.minY)
        let textWidth = base.width - padding * 2

        var size = min(maxFontSize, max(region.rect.height * 0.8, minFontSize))
        while size >= minFontSize {
            let needed = measure(panelText(region, size: size, colors: Colors(dark: false), number: nil), width: textWidth).height + padding
            if needed <= maxHeight {
                var frame = base
                frame.size.height = max(base.height, ceil(needed))
                return Panel(frame: frame, region: region, fontSize: size, padding: padding, fits: true)
            }
            size *= 0.9
        }

        var frame = base
        frame.size.height = maxHeight
        return Panel(frame: frame, region: region, fontSize: minFontSize, padding: padding, fits: false)
    }

    // MARK: - Text

    private struct Colors {
        let panel: UIColor
        let text: UIColor
        let footer: UIColor
        let note: UIColor
        let warning: UIColor

        init(dark: Bool) {
            panel = dark ? UIColor(white: 0.08, alpha: 0.9) : UIColor(white: 1, alpha: 0.94)
            text = dark ? .white : .black
            footer = dark ? UIColor(white: 0.08, alpha: 1) : .white
            note = dark ? UIColor(red: 0.45, green: 0.85, blue: 0.55, alpha: 1) : UIColor(red: 0.0, green: 0.45, blue: 0.2, alpha: 1)
            warning = dark ? UIColor(red: 1.0, green: 0.62, blue: 0.2, alpha: 1) : UIColor(red: 0.85, green: 0.35, blue: 0.0, alpha: 1)
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
        let prefix = number.map { "[\($0)] " } ?? ""
        let text = NSMutableAttributedString(attributedString: attributed(prefix + region.translated, size: size, color: colors.text))
        for note in region.notes {
            let color = note.hasPrefix("⚠") ? colors.warning : colors.note
            text.append(attributed("\n" + note, size: size * 0.8, color: color))
        }
        return text
    }

    private static func footerText(_ notes: [(number: Int, region: TranslatedRegion)], fontSize: CGFloat, colors: Colors) -> NSAttributedString {
        let text = NSMutableAttributedString()
        for (offset, note) in notes.enumerated() {
            if offset > 0 { text.append(attributed("\n\n", size: fontSize, color: colors.text)) }
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
