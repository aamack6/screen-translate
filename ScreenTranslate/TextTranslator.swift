import Foundation

/// Translates loose pieces of text (from the live camera or a web page), deciding for each which
/// language it's in, and adds converted prices when that's turned on.
enum TextTranslator {
    /// - Returns: original → text to show, for the texts that needed translating. Text that's
    ///   already in the user's language, or only numbers, has no entry.
    static func translate(_ texts: [String]) async -> [String: String] {
        let source = AppSettings.sourceLanguage
        let target = AppSettings.targetLanguage
        var lines = texts.map { TextLine(text: $0, rect: .zero) }
        LanguageDetector.assignLanguages(to: &lines, source: source, target: target)

        var result: [String: String] = [:]
        let foreign = lines.filter { $0.language != nil }
        for (language, group) in Dictionary(grouping: foreign, by: { $0.language! }) {
            let originals = Array(Set(group.map(\.text)))
            guard let translated = try? await Translator.translate(originals, from: language, to: target) else { continue }
            for (original, translation) in zip(originals, translated) {
                result[original] = translation
            }
        }

        let notes = await priceNotes(for: foreign.map { ($0.text, $0.language) })
        for (text, note) in notes {
            result[text] = "\(result[text] ?? text) (\(note))"
        }
        return result
    }

    /// "≈ $107.20" for each text with a foreign price, when price conversion is on.
    static func priceNotes(for items: [(text: String, language: AppLanguage?)]) async -> [String: String] {
        guard let options = AppSettings.priceOptions else { return [:] }
        var rates: [String: Double] = [:]
        var notes: [String: String] = [:]
        for item in items {
            var itemNotes: [String] = []
            for price in PriceParser.prices(in: item.text, language: item.language) where price.currency != options.currency {
                if rates[price.currency] == nil {
                    rates[price.currency] = await ExchangeRates.rate(from: price.currency, to: options.currency)
                }
                if let rate = rates[price.currency] {
                    itemNotes.append(ScreenTranslator.priceNote(price.amount * rate, options: options))
                }
            }
            if !itemNotes.isEmpty { notes[item.text] = itemNotes.joined(separator: ", ") }
        }
        return notes
    }
}
