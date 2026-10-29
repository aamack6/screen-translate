import CoreGraphics
import CoreVideo
import Vision

enum TextRecognizer {
    /// Finds lines of text in the image with Vision's on-device recognizer. Images much taller
    /// than a screen (joined screenshots) are read one screen-sized slice at a time, since Vision
    /// shrinks very tall images until small text can't be read.
    /// - Parameter language: the language to read, or nil to let Vision detect it.
    static func recognizeLines(in image: CGImage, language: AppLanguage?) throws -> [TextLine] {
        let width = CGFloat(image.width), height = CGFloat(image.height)
        let sliceHeight = (width * 2.2).rounded()
        guard height > sliceHeight * 1.2 else {
            let handler = VNImageRequestHandler(cgImage: image, orientation: .up, options: [:])
            return try recognizeLines(with: handler, imageSize: CGSize(width: width, height: height), language: language)
        }

        // Slices overlap so no line is cut in two; a line belongs to the slice holding its middle.
        let overlap = (width * 0.15).rounded()
        var lines: [TextLine] = []
        var top: CGFloat = 0
        while top < height {
            let bottom = min(top + sliceHeight, height)
            guard let slice = image.cropping(to: CGRect(x: 0, y: top, width: width, height: bottom - top)) else { break }
            let handler = VNImageRequestHandler(cgImage: slice, orientation: .up, options: [:])
            let ownedTop = top == 0 ? 0 : top + overlap / 2
            let ownedBottom = bottom >= height ? height : bottom - overlap / 2
            for line in try recognizeLines(with: handler, imageSize: CGSize(width: width, height: bottom - top), language: language) {
                let rect = line.rect.offsetBy(dx: 0, dy: top)
                if rect.midY >= ownedTop, rect.midY < ownedBottom {
                    lines.append(TextLine(text: line.text, rect: rect, confidence: line.confidence))
                }
            }
            if bottom >= height { break }
            top = bottom - overlap
        }
        return lines
    }

    /// Same, for a frame of the screen broadcast. Rects are in the frame as the user sees it,
    /// with `orientation` applied.
    static func recognizeLines(in pixelBuffer: CVPixelBuffer, orientation: CGImagePropertyOrientation, language: AppLanguage?) throws -> [TextLine] {
        let handler = VNImageRequestHandler(cvPixelBuffer: pixelBuffer, orientation: orientation, options: [:])
        return try recognizeLines(with: handler, imageSize: orientedSize(of: pixelBuffer, orientation: orientation), language: language)
    }

    static func orientedSize(of pixelBuffer: CVPixelBuffer, orientation: CGImagePropertyOrientation) -> CGSize {
        let width = CGFloat(CVPixelBufferGetWidth(pixelBuffer))
        let height = CGFloat(CVPixelBufferGetHeight(pixelBuffer))
        switch orientation {
        case .left, .leftMirrored, .right, .rightMirrored: return CGSize(width: height, height: width)
        default: return CGSize(width: width, height: height)
        }
    }

    private static func recognizeLines(with handler: VNImageRequestHandler, imageSize size: CGSize, language: AppLanguage?) throws -> [TextLine] {
        let request = VNRecognizeTextRequest()
        request.recognitionLevel = .accurate
        request.usesLanguageCorrection = true
        if let visionLanguage = language?.visionLanguage {
            request.recognitionLanguages = [visionLanguage]
            request.automaticallyDetectsLanguage = false
        } else {
            request.automaticallyDetectsLanguage = true
        }

        try handler.perform([request])

        return (request.results ?? []).compactMap { observation in
            guard let candidate = observation.topCandidates(1).first else { return nil }
            let text = candidate.string.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !text.isEmpty else { return nil }
            return TextLine(
                text: text,
                rect: TextGeometry.topLeftFrame(fromVision: observation.boundingBox, imageSize: size),
                confidence: candidate.confidence
            )
        }
    }
}
