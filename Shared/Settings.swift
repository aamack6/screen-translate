import Foundation
import NaturalLanguage

/// Every language the app knows. All of them can be translated into; the ones Vision can read
/// (`isReadable`) can also be translated from. Translation itself is Apple's on-device
/// Translation framework, and a pair Apple doesn't support shows as "Not available".
enum AppLanguage: String, CaseIterable, Identifiable, Codable {
    case english = "en"
    case spanish = "es"
    case french = "fr"
    case german = "de"
    case italian = "it"
    case portuguese = "pt-BR"
    case russian = "ru"
    case ukrainian = "uk"
    case japanese = "ja"
    case chineseSimplified = "zh-Hans"
    case chineseTraditional = "zh-Hant"
    case korean = "ko"
    case thai = "th"
    case vietnamese = "vi"
    case arabic = "ar"
    case dutch = "nl"
    case polish = "pl"
    case turkish = "tr"
    case indonesian = "id"
    case hindi = "hi"

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .english: return "English"
        case .spanish: return "Spanish"
        case .french: return "French"
        case .german: return "German"
        case .italian: return "Italian"
        case .portuguese: return "Portuguese"
        case .russian: return "Russian"
        case .ukrainian: return "Ukrainian"
        case .japanese: return "Japanese"
        case .chineseSimplified: return "Chinese (Simplified)"
        case .chineseTraditional: return "Chinese (Traditional)"
        case .korean: return "Korean"
        case .thai: return "Thai"
        case .vietnamese: return "Vietnamese"
        case .arabic: return "Arabic"
        case .dutch: return "Dutch"
        case .polish: return "Polish"
        case .turkish: return "Turkish"
        case .indonesian: return "Indonesian"
        case .hindi: return "Hindi"
        }
    }

    var localeLanguage: Locale.Language { Locale.Language(identifier: rawValue) }

    /// Vision's identifier for reading this language from an image, or nil if it can't.
    var visionLanguage: String? {
        switch self {
        case .english: return "en-US"
        case .spanish: return "es-ES"
        case .french: return "fr-FR"
        case .german: return "de-DE"
        case .italian: return "it-IT"
        case .portuguese: return "pt-BR"
        case .russian: return "ru-RU"
        case .ukrainian: return "uk-UA"
        case .japanese: return "ja-JP"
        case .chineseSimplified: return "zh-Hans"
        case .chineseTraditional: return "zh-Hant"
        case .korean: return "ko-KR"
        case .thai: return "th-TH"
        case .vietnamese: return "vi-VT"
        case .arabic: return "ar-SA"
        case .dutch, .polish, .turkish, .indonesian, .hindi: return nil
        }
    }

    var isReadable: Bool { visionLanguage != nil }

    static var readable: [AppLanguage] { allCases.filter(\.isReadable) }

    /// NaturalLanguage's identifier, used to detect which language a piece of text is in.
    var nlLanguage: NLLanguage {
        switch self {
        case .chineseSimplified: return .simplifiedChinese
        case .chineseTraditional: return .traditionalChinese
        case .portuguese: return .portuguese
        default: return NLLanguage(rawValue: rawValue)
        }
    }

    /// How two recognized lines of the same paragraph are joined before translating.
    /// Japanese, Chinese and Thai don't put spaces between words.
    var lineJoiner: String {
        switch self {
        case .japanese, .chineseSimplified, .chineseTraditional, .thai: return ""
        default: return " "
        }
    }

    var script: Script {
        switch self {
        case .japanese: return .japanese
        case .chineseSimplified, .chineseTraditional: return .han
        case .korean: return .hangul
        case .russian, .ukrainian: return .cyrillic
        case .thai: return .thai
        case .arabic: return .arabic
        case .hindi: return .devanagari
        default: return .latin
        }
    }

    /// What ¥ and 元 most likely mean in text written in this language.
    var yenCurrency: String {
        switch self {
        case .chineseSimplified: return "CNY"
        case .chineseTraditional: return "TWD"
        default: return "JPY"
        }
    }
}

/// Writing systems, used to tell which text on screen needs translating.
enum Script {
    case latin, japanese, han, hangul, cyrillic, thai, arabic, devanagari

    /// True when the text contains at least one character of this script.
    func occurs(in text: String) -> Bool {
        text.unicodeScalars.contains { scalar in
            let v = scalar.value
            switch self {
            case .japanese: return Script.isKana(v) || Script.isHan(v)
            case .han: return Script.isHan(v)
            case .hangul: return (0xAC00...0xD7AF).contains(v) || (0x1100...0x11FF).contains(v) || (0x3130...0x318F).contains(v)
            case .cyrillic: return (0x0400...0x04FF).contains(v)
            case .thai: return (0x0E00...0x0E7F).contains(v)
            case .arabic: return (0x0600...0x06FF).contains(v) || (0x0750...0x077F).contains(v)
            case .devanagari: return (0x0900...0x097F).contains(v)
            case .latin: return (0x41...0x5A).contains(v) || (0x61...0x7A).contains(v) || (0xC0...0x24F).contains(v)
            }
        }
    }

    static func isKana(_ v: UInt32) -> Bool { (0x3040...0x30FF).contains(v) || (0xFF66...0xFF9F).contains(v) }
    static func isHan(_ v: UInt32) -> Bool { (0x4E00...0x9FFF).contains(v) || (0x3400...0x4DBF).contains(v) }
}

/// Currencies prices can be converted into. Until the user picks one, the phone's own currency is used.
enum DisplayCurrency {
    static let codes = [
        "USD", "EUR", "GBP", "JPY", "CNY", "KRW", "TWD", "HKD", "SGD", "AUD", "NZD", "CAD",
        "CHF", "INR", "BRL", "MXN", "THB", "PHP", "VND", "IDR", "TRY", "PLN", "SEK", "RUB", "UAH",
    ]

    static var deviceDefault: String {
        let code = Locale.current.currency?.identifier ?? "USD"
        return codes.contains(code) ? code : "USD"
    }

    static func format(_ amount: Double, code: String) -> String {
        amount.formatted(.currency(code: code))
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
    static let lastDetectedSource = "lastDetectedSource"
    static let onlineEngine = "onlineEngine"
    static let rememberTranslations = "rememberTranslations"
}

/// Stored source-language value meaning "detect the language automatically".
let autoDetectSetting = "auto"

/// Reads the settings the user chose in the app. The Shortcuts action runs in the
/// app's own process, so it sees the same values.
enum AppSettings {
    private static var defaults: UserDefaults { .standard }

    /// Nil = detect automatically (the default).
    static var sourceLanguage: AppLanguage? {
        AppLanguage(rawValue: defaults.string(forKey: SettingsKey.sourceLanguage) ?? autoDetectSetting)
    }

    /// With automatic detection, the language most of the last screenshot was in: the best guess
    /// for which translation model to start loading before the text has been read.
    static var lastDetectedSource: AppLanguage? {
        get { defaults.string(forKey: SettingsKey.lastDetectedSource).flatMap(AppLanguage.init(rawValue:)) }
        set { defaults.set(newValue?.rawValue, forKey: SettingsKey.lastDetectedSource) }
    }

    /// Defaults to the phone's language when the app supports it, otherwise English.
    static var targetLanguage: AppLanguage {
        AppLanguage(rawValue: defaults.string(forKey: SettingsKey.targetLanguage) ?? "") ?? deviceLanguage
    }

    static var deviceLanguage: AppLanguage {
        let code = Locale.current.language.languageCode?.identifier ?? "en"
        return AppLanguage.allCases.first { $0.localeLanguage.languageCode?.identifier == code } ?? .english
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
            currency: defaults.string(forKey: SettingsKey.displayCurrency) ?? DisplayCurrency.deviceDefault,
            extraCost: max(defaults.double(forKey: SettingsKey.extraCost), 0)
        )
    }

    /// On unless the user turned it off.
    static var flagListingTerms: Bool { defaults.object(forKey: SettingsKey.flagListingTerms) as? Bool ?? true }
}

struct PriceOptions {
    /// ISO code of the currency to show prices in, such as "USD".
    var currency: String
    /// Fees added to every converted price (proxy service, shipping), in `currency`. 0 = none.
    var extraCost: Double
}

struct OverlayOptions {
    /// Dark panels with white text instead of white panels with black text.
    var darkPanels = false
    /// List every translation under the image, not only the ones that didn't fit.
    var appendFullText = false
}
