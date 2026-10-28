import CoreGraphics
import Vision

enum TextRecognizer {
    /// Finds lines of text in the image with Vision's on-device recognizer.
    static func recognizeLines(in image: CGImage, language: SourceLanguage) throws -> [TextLine] {
        let request = VNRecognizeTextRequest()
        request.recognitionLevel = .accurate
        request.recognitionLanguages = language.visionLanguages
        request.automaticallyDetectsLanguage = false
        request.usesLanguageCorrection = true

        let handler = VNImageRequestHandler(cgImage: image, orientation: .up, options: [:])
        try handler.perform([request])

        let size = CGSize(width: image.width, height: image.height)
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
