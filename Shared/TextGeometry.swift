import CoreGraphics

/// One line of text found by Vision, in image pixels with the origin at the top left.
struct TextLine {
    let text: String
    let rect: CGRect
    /// The language to translate this line from; nil = leave it untranslated (prices only).
    var language: AppLanguage?
}

/// Neighbouring lines merged into one paragraph, so sentences that wrap are translated whole.
struct TextBlock {
    var lines: [TextLine]
    var rect: CGRect

    init(line: TextLine) {
        lines = [line]
        rect = line.rect
    }

    var language: AppLanguage? { lines.first?.language }

    var text: String {
        lines.map(\.text).joined(separator: language?.lineJoiner ?? " ")
    }

    mutating func append(_ line: TextLine) {
        lines.append(line)
        rect = rect.union(line.rect)
    }
}

enum TextGeometry {
    /// Converts Vision's normalized, bottom-left-origin box to pixels with a top-left origin.
    static func topLeftFrame(fromVision box: CGRect, imageSize: CGSize) -> CGRect {
        CGRect(
            x: box.minX * imageSize.width,
            y: (1 - box.maxY) * imageSize.height,
            width: box.width * imageSize.width,
            height: box.height * imageSize.height
        )
    }

    /// True for text inside the status bar (clock, carrier) of a portrait screenshot.
    static func isInStatusBar(_ rect: CGRect, imageSize: CGSize) -> Bool {
        guard imageSize.height > imageSize.width else { return false }
        return rect.maxY < imageSize.height * 0.045
    }

    /// Groups lines into paragraphs: a line joins a block when it's in the same language, sits just
    /// below the block's last line, has a similar height, and overlaps it horizontally.
    static func groupIntoBlocks(_ lines: [TextLine]) -> [TextBlock] {
        let sorted = lines.sorted { $0.rect.minY < $1.rect.minY }
        var blocks: [TextBlock] = []

        for line in sorted {
            let index = blocks.lastIndex { block in
                guard let last = block.lines.last, last.language == line.language else { return false }
                return continues(last.rect, with: line.rect)
            }
            if let index {
                blocks[index].append(line)
            } else {
                blocks.append(TextBlock(line: line))
            }
        }
        return blocks
    }

    private static func continues(_ previous: CGRect, with next: CGRect) -> Bool {
        let height = min(previous.height, next.height)
        guard height > 0 else { return false }

        let gap = next.minY - previous.maxY
        let similarHeight = max(previous.height, next.height) / height < 1.5
        let closeBelow = gap > -height * 0.5 && gap < height * 0.8
        let overlapsHorizontally = next.minX < previous.maxX && previous.minX < next.maxX
        let sameLeftEdge = abs(next.minX - previous.minX) < height * 1.5

        return similarHeight && closeBelow && (overlapsHorizontally || sameLeftEdge)
    }
}
