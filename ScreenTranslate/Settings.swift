import Foundation

/// Languages the app can read from a screenshot.
enum SourceLanguage: String, CaseIterable, Identifiable, Codable {
    case japanese = "ja"
    case chineseSimplified = "zh-Hans"
    case chineseTraditional = "zh-Hant"
    case korean = "ko"

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .japanese: return "Japanese"
        case .chineseSimplified: return "Chinese (Simplified)"
        case .chineseTraditional: return "Chinese (Traditional)"
        case .korean: return "Korean"
        }
    }

    var localeLanguage: Locale.Language { Locale.Language(identifier: rawValue) }

    /// Identifiers Vision's text recognizer expects.
    var visionLanguages: [String] {
        switch self {
        case .japanese: return ["ja-JP"]
        case .chineseSimplified: return ["zh-Hans"]
        case .chineseTraditional: return ["zh-Hant"]
        case .korean: return ["ko-KR"]
        }
    }

    /// How two recognized lines of the same paragraph are joined before translating.
    /// Japanese and Chinese don't put spaces between words; Korean does.
    var lineJoiner: String { self == .korean ? " " : "" }

    /// The currency prices in this language are usually written in.
    var homeCurrency: String {
        switch self {
        case .japanese: return "JPY"
        case .chineseSimplified: return "CNY"
        case .chineseTraditional: return "TWD"
        case .korean: return "KRW"
        }
    }

    /// True when the text contains at least one character of this language's script.
    /// Used to leave English, numbers and symbols on the screenshot untouched.
    func matchesScript(_ text: String) -> Bool {
        text.unicodeScalars.contains { scalar in
            let v = scalar.value
            let isHan = (0x4E00...0x9FFF).contains(v) || (0x3400...0x4DBF).contains(v)
            let isKana = (0x3040...0x30FF).contains(v) || (0xFF66...0xFF9F).contains(v)
            let isHangul = (0xAC00...0xD7AF).contains(v) || (0x1100...0x11FF).contains(v)
                || (0x3130...0x318F).contains(v)
            switch self {
            case .japanese: return isKana || isHan
            case .chineseSimplified, .chineseTraditional: return isHan
            case .korean: return isHangul
            }
        }
    }
}

/// Languages the app translates into. All are handled by Apple's on-device Translation;
/// a pair Apple doesn't support shows as "Not available" in the app.
enum TargetLanguage: String, CaseIterable, Identifiable, Codable {
    case english = "en"
    case spanish = "es"
    case french = "fr"
    case german = "de"
    case italian = "it"
    case portuguese = "pt-BR"
    case dutch = "nl"
    case polish = "pl"
    case turkish = "tr"
    case indonesian = "id"
    case vietnamese = "vi"
    case thai = "th"

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .english: return "English"
        case .spanish: return "Spanish"
        case .french: return "French"
        case .german: return "German"
        case .italian: return "Italian"
        case .portuguese: return "Portuguese"
        case .dutch: return "Dutch"
        case .polish: return "Polish"
        case .turkish: return "Turkish"
        case .indonesian: return "Indonesian"
        case .vietnamese: return "Vietnamese"
        case .thai: return "Thai"
        }
    }

    var localeLanguage: Locale.Language { Locale.Language(identifier: rawValue) }
}

/// Currencies prices can be converted into.
enum DisplayCurrency: String, CaseIterable, Identifiable, Codable {
    case usd = "USD"
    case eur = "EUR"
    case gbp = "GBP"
    case cad = "CAD"
    case aud = "AUD"
    case nzd = "NZD"
    case sgd = "SGD"
    case hkd = "HKD"
    case jpy = "JPY"

    var id: String { rawValue }

    func format(_ amount: Double) -> String {
        amount.formatted(.currency(code: rawValue).precision(.fractionLength(rawValue == "JPY" ? 0 : 2)))
    }
}

enum SettingsKey {
    static let sourceLanguage = "sourceLanguage"
    static let targetLanguage = "targetLanguage"
    static let convertPrices = "convertPrices"
    static let displayCurrency = "displayCurrency"
    static let extraCost = "extraCost"
    static let flagListingTerms = "flagListingTerms"
    static let darkPanels = "darkPanels"
    static let appendFullText = "appendFullText"
    static let keepHistory = "keepHistory"
}

/// Reads the settings the user chose in the app. The Shortcuts action runs in the
/// app's own process, so it sees the same values.
enum AppSettings {
    private static var defaults: UserDefaults { .standard }

    static var sourceLanguage: SourceLanguage {
        SourceLanguage(rawValue: defaults.string(forKey: SettingsKey.sourceLanguage) ?? "") ?? .japanese
    }

    static var targetLanguage: TargetLanguage {
        TargetLanguage(rawValue: defaults.string(forKey: SettingsKey.targetLanguage) ?? "") ?? .english
    }

    static var keepHistory: Bool { defaults.bool(forKey: SettingsKey.keepHistory) }

    static var overlayOptions: OverlayOptions {
        OverlayOptions(
            darkPanels: defaults.bool(forKey: SettingsKey.darkPanels),
            appendFullText: defaults.bool(forKey: SettingsKey.appendFullText)
        )
    }

    /// Nil when price conversion is turned off.
    static var priceOptions: PriceOptions? {
        guard defaults.bool(forKey: SettingsKey.convertPrices) else { return nil }
        return PriceOptions(
            currency: DisplayCurrency(rawValue: defaults.string(forKey: SettingsKey.displayCurrency) ?? "") ?? .usd,
            extraCost: max(defaults.double(forKey: SettingsKey.extraCost), 0)
        )
    }

    /// On unless the user turned it off.
    static var flagListingTerms: Bool { defaults.object(forKey: SettingsKey.flagListingTerms) as? Bool ?? true }
}

struct PriceOptions {
    var currency: DisplayCurrency
    /// Fees added to every price before converting (proxy service, domestic shipping),
    /// in the screenshot's currency. 0 = none.
    var extraCost: Double
}

struct OverlayOptions {
    /// Dark panels with white text instead of white panels with black text.
    var darkPanels = false
    /// List every translation under the image, not only the ones that didn't fit.
    var appendFullText = false
}
