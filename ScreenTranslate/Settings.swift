import Foundation

/// Languages the app can read from a screenshot. Translations always go to English.
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

enum SettingsKey {
    static let sourceLanguage = "sourceLanguage"
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

    static var keepHistory: Bool { defaults.bool(forKey: SettingsKey.keepHistory) }

    static var overlayOptions: OverlayOptions {
        OverlayOptions(
            darkPanels: defaults.bool(forKey: SettingsKey.darkPanels),
            appendFullText: defaults.bool(forKey: SettingsKey.appendFullText)
        )
    }
}

struct OverlayOptions {
    /// Dark panels with white text instead of white panels with black text.
    var darkPanels = false
    /// List every translation under the image, not only the ones that didn't fit.
    var appendFullText = false
}
