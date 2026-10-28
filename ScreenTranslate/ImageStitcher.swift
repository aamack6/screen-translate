import CoreGraphics

/// Joins screenshots taken while scrolling down a page into one long image. Each screenshot is
/// matched against the one before it: parts that stay put (status bar, app header, tab bar) are
/// kept once, and the overlapping content is found by sliding one screenshot over the other.
enum ImageStitcher {
    /// Width of the small grayscale copies used for matching. About 7 screen pixels per row on a
    /// modern iPhone, which is plenty to line up text.
    private static let sampleWidth = 200

    /// - Returns: the joined image, without the status bar of the first screenshot.
    static func stitch(_ screenshots: [CGImage]) -> CGImage? {
        guard let first = screenshots.first else { return nil }
        let width = first.width
        let images = screenshots.compactMap { scaled($0, toWidth: width) }
        guard images.count == screenshots.count else { return nil }
        let samples = images.compactMap { Sample($0, width: sampleWidth) }
        guard samples.count == images.count else { return nil }

        // Rows of each screenshot to keep, top to bottom.
        let statusBar = first.height > first.width ? Int(Double(first.height) * 0.05) : 0
        var segments: [(image: Int, top: Int, bottom: Int)] = [(0, statusBar, images[0].height)]

        for index in 1..<images.count {
            let previous = samples[index - 1], current = samples[index]
            let header = matchingRows(previous, current, fromTop: true)
            let footer = matchingRows(previous, current, fromTop: false)
            // End the previous screenshot above its footer; the last one keeps it.
            let previousEnd = fullRow(previous.height - footer, of: images[index - 1], sample: previous)
            segments[segments.count - 1].bottom = previousEnd
            let headerEnd = fullRow(header, of: images[index], sample: current)
            let currentEnd = fullRow(current.height - footer, of: images[index], sample: current)

            var top = headerEnd // No overlap found: add the whole content area.
            if let roughShift = scrollShift(previous, current, header: header, footer: footer) {
                // Row y of this screenshot shows what was at row y + shift in the previous one.
                // The small samples place it within a few pixels; finish at full size so the
                // seam doesn't cut through a line of text.
                let shift = refinedShift(
                    images[index - 1], images[index],
                    near: fullRow(roughShift, of: images[index - 1], sample: previous),
                    rows: headerEnd..<currentEnd, previousEnd: previousEnd
                )
                top = max(previousEnd - shift, headerEnd)
            }
            if top < images[index].height {
                segments.append((index, top, images[index].height))
            }
        }

        let totalHeight = segments.reduce(0) { $0 + max($1.bottom - $1.top, 0) }
        guard totalHeight > 0, let context = CGContext(
            data: nil, width: width, height: totalHeight, bitsPerComponent: 8, bytesPerRow: 0,
            space: CGColorSpaceCreateDeviceRGB(), bitmapInfo: CGImageAlphaInfo.noneSkipLast.rawValue
        ) else { return nil }

        var y = 0
        for segment in segments where segment.bottom > segment.top {
            let height = segment.bottom - segment.top
            guard let piece = images[segment.image].cropping(to: CGRect(x: 0, y: segment.top, width: width, height: height)) else { continue }
            // Core Graphics draws from the bottom up.
            context.draw(piece, in: CGRect(x: 0, y: totalHeight - y - height, width: width, height: height))
            y += height
        }
        return context.makeImage()
    }

    // MARK: - Matching

    /// A small grayscale copy of a screenshot, one byte per pixel.
    private struct Sample {
        let pixels: [UInt8]
        let width: Int
        let height: Int

        init?(_ image: CGImage, width: Int) {
            self.width = width
            height = max(Int((Double(image.height) * Double(width) / Double(image.width)).rounded()), 1)
            var pixels = [UInt8](repeating: 0, count: width * height)
            let drawn = pixels.withUnsafeMutableBytes { buffer -> Bool in
                guard let context = CGContext(
                    data: buffer.baseAddress, width: width, height: height, bitsPerComponent: 8, bytesPerRow: width,
                    space: CGColorSpaceCreateDeviceGray(), bitmapInfo: CGImageAlphaInfo.none.rawValue
                ) else { return false }
                context.interpolationQuality = .medium
                context.draw(image, in: CGRect(x: 0, y: 0, width: width, height: height))
                return true
            }
            guard drawn else { return nil }
            self.pixels = pixels
        }

        /// Average difference between a row here and a row of another sample of the same width,
        /// 0...255, looking at every `step`th pixel.
        func difference(row: Int, from other: Sample, row otherRow: Int, step: Int = 1) -> Int {
            var total = 0, count = 0
            let a = row * width, b = otherRow * other.width
            for x in stride(from: 0, to: width, by: step) {
                total += abs(Int(pixels[a + x]) - Int(other.pixels[b + x]))
                count += 1
            }
            return total / max(count, 1)
        }
    }

    /// How many rows at the top (or bottom) are the same in both screenshots: the parts of the
    /// screen that don't scroll. Capped at 40% of the screen.
    private static func matchingRows(_ a: Sample, _ b: Sample, fromTop: Bool) -> Int {
        let limit = min(a.height, b.height) * 2 / 5
        var count = 0
        while count < limit {
            let rowA = fromTop ? count : a.height - 1 - count
            let rowB = fromTop ? count : b.height - 1 - count
            if a.difference(row: rowA, from: b, row: rowB) > 2 { break }
            count += 1
        }
        return count
    }

    /// How far the content scrolled between two screenshots, in sample rows, or nil when they
    /// don't overlap.
    private static func scrollShift(_ previous: Sample, _ current: Sample, header: Int, footer: Int) -> Int? {
        let previousEnd = previous.height - footer
        let currentEnd = current.height - footer
        let content = previousEnd - header
        let minimumOverlap = max(content / 10, 8)
        guard content > minimumOverlap else { return nil }

        var best: (shift: Int, cost: Double)?
        for shift in 1...(content - minimumOverlap) {
            let rows = min(currentEnd, previousEnd - shift) - header
            guard rows >= minimumOverlap else { continue }
            var total = 0
            // Every other row is enough to tell positions apart, at half the work.
            for y in stride(from: header, to: header + rows, by: 2) {
                total += current.difference(row: y, from: previous, row: y + shift)
            }
            let cost = Double(total) / Double((rows + 1) / 2)
            if cost < (best?.cost ?? .infinity) {
                best = (shift, cost)
            }
        }
        guard let best, best.cost < 6 else { return nil }
        return best.shift
    }

    /// Finds the exact scroll distance in full-size pixels, within a few pixels of `near`.
    private static func refinedShift(_ previousImage: CGImage, _ currentImage: CGImage, near: Int, rows: Range<Int>, previousEnd: Int) -> Int {
        guard let previous = Sample(previousImage, width: previousImage.width),
              let current = Sample(currentImage, width: currentImage.width) else { return near }
        let window = max(previousImage.height / sampleWidth, 4) * 2
        var best = (shift: near, cost: Int.max)
        for shift in (near - window)...(near + window) where shift > 0 {
            let end = min(rows.upperBound, previousEnd - shift)
            guard end - rows.lowerBound > 20 else { continue }
            var total = 0
            for y in stride(from: rows.lowerBound, to: end, by: 3) {
                total += current.difference(row: y, from: previous, row: y + shift, step: 2)
            }
            let cost = total / ((end - rows.lowerBound + 2) / 3)
            if cost < best.cost {
                best = (shift, cost)
            }
        }
        return best.shift
    }

    // MARK: - Helpers

    /// Converts a row of a small matching sample to a row of the full-size image.
    private static func fullRow(_ sampleRow: Int, of image: CGImage, sample: Sample) -> Int {
        Int((Double(sampleRow) * Double(image.height) / Double(sample.height)).rounded())
    }

    private static func scaled(_ image: CGImage, toWidth width: Int) -> CGImage? {
        guard image.width != width else { return image }
        let height = Int((Double(image.height) * Double(width) / Double(image.width)).rounded())
        guard let context = CGContext(
            data: nil, width: width, height: height, bitsPerComponent: 8, bytesPerRow: 0,
            space: CGColorSpaceCreateDeviceRGB(), bitmapInfo: CGImageAlphaInfo.noneSkipLast.rawValue
        ) else { return nil }
        context.interpolationQuality = .high
        context.draw(image, in: CGRect(x: 0, y: 0, width: width, height: height))
        return context.makeImage()
    }
}

