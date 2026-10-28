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

    /// Assigns each line the language to translate it from (nil = leave it), looking at the whole
    /// screen rather than one line at a time. With automatic detection, short lines are easily
    /// mistaken: "Comments (2)" or a user name read as French, a few kanji read as Chinese on a
    /// Japanese page. Each wrong language is a wrong translation plus another model to load, so:
    /// - text in the target's own alphabet is only translated when it's clearly another language,
    ///   or the page is mostly in a language that shares that alphabet;
    /// - other doubtful lines are taken to be in the screen's main language.
    static func assignLanguages(to lines: inout [TextLine], source: AppLanguage?, target: AppLanguage) {
        for index in lines.indices {
            lines[index].language = sourceLanguage(of: lines[index].text, source: source, target: target)
        }
        guard source == nil else { return }

        let candidates = AppLanguage.readable + [target]
        // The screen's main language, counted only from lines that are surely foreign: another
        // writing system, or clearly another language.
        var letters: [AppLanguage: Int] = [:]
        for line in lines {
            guard let language = line.language else { continue }
            if language.script != target.script || isClearly(line.text, language, among: candidates) {
                letters[language, default: 0] += line.text.filter(\.isLetter).count
            }
        }
        let main = letters.max(by: { $0.value < $1.value })?.key

        for index in lines.indices {
            guard let language = lines[index].language, language != main else { continue }
            let text = lines[index].text
            if isClearly(text, language, among: candidates) { continue }
            if language.script == target.script {
                // A short label like "Inicio" on a Spanish page is Spanish; on a Japanese page,
                // short Latin text is names, numbers and English UI. Leave it.
                lines[index].language = main?.script == target.script ? main : nil
            } else if let main, language.script == main.script || (main == .japanese && language.script == .han),
                      !text.unicodeScalars.contains(where: { Script.isKana($0.value) }) {
                lines[index].language = main
            }
        }
    }

    /// True for text of at least three words that the recognizer is quite sure is `language`.
    private static func isClearly(_ text: String, _ language: AppLanguage, among candidates: [AppLanguage]) -> Bool {
        let words = text.split { !$0.isLetter }.filter { $0.count > 1 }
        guard words.count >= 3 else { return false }
        let recognizer = NLLanguageRecognizer()
        recognizer.languageConstraints = candidates.map(\.nlLanguage)
        recognizer.processString(text)
        return (recognizer.languageHypotheses(withMaximum: 1)[language.nlLanguage] ?? 0) >= 0.8
    }

    private static func detect(_ text: String, among candidates: [AppLanguage]) -> AppLanguage? {
        let recognizer = NLLanguageRecognizer()
        recognizer.languageConstraints = candidates.map(\.nlLanguage)
        recognizer.processString(text)
        guard let language = recognizer.dominantLanguage else { return nil }
        return candidates.first { $0.nlLanguage == language }
    }
}
