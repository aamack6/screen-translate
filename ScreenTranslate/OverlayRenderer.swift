import UIKit

struct TranslatedRegion: Codable {
    let original: String
    let translated: String
    let rect: CGRect
}

/// Draws English panels over the original text. Translations too long for their panel get a
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
        var footnotes: [(number: Int, text: String)] = []
        for region in regions {
            var panel = layoutPanel(for: region, minFontSize: minFontSize, maxFontSize: maxFontSize, imageHeight: height)
            if !panel.fits || options.appendFullText {
                let number = footnotes.count + 1
                footnotes.append((number, region.translated))
                if !panel.fits {
                    panel.number = number
                }
            }
            panels.append(panel)
        }

        let footer = footerText(footnotes, fontSize: minFontSize * 1.1, color: colors.text)
        let footerPadding = minFontSize
        let footerHeight = footnotes.isEmpty ? 0 : ceil(measure(footer, width: width - footerPadding * 2).height) + footerPadding * 2

        let format = UIGraphicsImageRendererFormat()
        format.scale = 1
        format.opaque = true
        let renderer = UIGraphicsImageRenderer(size: CGSize(width: width, height: height + footerHeight), format: format)

        return renderer.pngData { context in
            UIImage(cgImage: image).draw(in: CGRect(x: 0, y: 0, width: width, height: height))

            for panel in panels {
                colors.panel.setFill()
                UIBezierPath(roundedRect: panel.frame, cornerRadius: min(panel.frame.height * 0.2, minFontSize * 0.6)).fill()
                let text = panel.number.map { attributed("[\($0)] \(panel.text)", size: panel.fontSize, color: colors.text) }
                    ?? attributed(panel.text, size: panel.fontSize, color: colors.text)
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
        var text: String
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
            let needed = measure(attributed(region.translated, size: size, color: .black), width: textWidth).height + padding
            if needed <= maxHeight {
                var frame = base
                frame.size.height = max(base.height, ceil(needed))
                return Panel(frame: frame, text: region.translated, fontSize: size, padding: padding, fits: true)
            }
            size *= 0.9
        }

        var frame = base
        frame.size.height = maxHeight
        return Panel(frame: frame, text: region.translated, fontSize: minFontSize, padding: padding, fits: false)
    }

    // MARK: - Text

    private struct Colors {
        let panel: UIColor
        let text: UIColor
        let footer: UIColor

        init(dark: Bool) {
            panel = dark ? UIColor(white: 0.08, alpha: 0.9) : UIColor(white: 1, alpha: 0.94)
            text = dark ? .white : .black
            footer = dark ? UIColor(white: 0.08, alpha: 1) : .white
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

    private static func footerText(_ notes: [(number: Int, text: String)], fontSize: CGFloat, color: UIColor) -> NSAttributedString {
        let body = notes.map { "[\($0.number)] \($0.text)" }.joined(separator: "\n\n")
        return attributed(body, size: fontSize, color: color)
    }

    private static func measure(_ text: NSAttributedString, width: CGFloat) -> CGRect {
        text.boundingRect(
            with: CGSize(width: max(width, 1), height: .greatestFiniteMagnitude),
            options: [.usesLineFragmentOrigin],
            context: nil
        )
    }
}
