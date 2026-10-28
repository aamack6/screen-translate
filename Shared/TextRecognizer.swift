import CoreGraphics
import CoreVideo
import Vision

enum TextRecognizer {
    /// Finds lines of text in the image with Vision's on-device recognizer.
    /// - Parameter language: the language to read, or nil to let Vision detect it.
    static func recognizeLines(in image: CGImage, language: AppLanguage?) throws -> [TextLine] {
        let handler = VNImageRequestHandler(cgImage: image, orientation: .up, options: [:])
        return try recognizeLines(with: handler, imageSize: CGSize(width: image.width, height: image.height), language: language)
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
                rect: TextGeometry.topLeftFrame(fromVision: observation.boundingBox, imageSize: size)
            )
        }
    }
}
