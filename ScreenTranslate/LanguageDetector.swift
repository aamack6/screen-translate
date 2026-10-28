import NaturalLanguage

/// Decides which recognized text needs translating, and from which language.
enum LanguageDetector {
    /// The language to translate `text` from, or nil to leave it as it is (it's already in the
    /// target language, or it's only numbers and symbols).
    /// - Parameter source: the language the user picked, or nil for automatic detection.
    static func sourceLanguage(of text: String, source: AppLanguage?, target: AppLanguage) -> AppLanguage? {
        guard text.contains(where: \.isLetter) else { return nil }

        if let source {
            guard source != target else { return nil }
            // A different writing system is the most reliable signal, even for short text.
            if source.script != target.script {
                return source.script.occurs(in: text) ? source : nil
            }
            return detect(text, among: [source, target]) == source ? source : nil
        }

        // Kana only appears in Japanese, and NaturalLanguage sometimes calls short kanji text Chinese.
        if text.unicodeScalars.contains(where: { Script.isKana($0.value) }) {
            return target == .japanese ? nil : .japanese
        }
        guard let detected = detect(text, among: AppLanguage.readable + [target]), detected != target else { return nil }
        // Text in the target's writing system that the detector can't place confidently is most
        // likely names or brand words in the target language; leave it.
        if detected.script == target.script, text.count < 4 { return nil }
        return detected.isReadable ? detected : nil
    }

    private static func detect(_ text: String, among candidates: [AppLanguage]) -> AppLanguage? {
        let recognizer = NLLanguageRecognizer()
        recognizer.languageConstraints = candidates.map(\.nlLanguage)
        recognizer.processString(text)
        guard let language = recognizer.dominantLanguage else { return nil }
        return candidates.first { $0.nlLanguage == language }
    }
}
