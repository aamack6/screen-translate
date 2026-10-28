import AppIntents
import UniformTypeIdentifiers

/// The Shortcuts action. A shortcut on the Action Button runs:
/// Take Screenshot → Translate Screenshot → Quick Look.
struct TranslateScreenshotIntent: AppIntent {
    static let title: LocalizedStringResource = "Translate Screenshot"
    static let description = IntentDescription(
        "Finds text in a screenshot, translates it on this iPhone, and returns the screenshot with the translation drawn over the original text. Download the languages in ScreenTranslate first."
    )
    static let openAppWhenRun = false

    @Parameter(title: "Screenshot", supportedContentTypes: [.image])
    var screenshot: IntentFile

    @Parameter(title: "From", description: "Leave empty to use the language chosen in the app.")
    var language: SourceLanguage?

    @Parameter(title: "To", description: "Leave empty to use the language chosen in the app.")
    var target: TargetLanguage?

    static var parameterSummary: some ParameterSummary {
        Summary("Translate \(\.$screenshot)") {
            \.$language
            \.$target
        }
    }

    func perform() async throws -> some IntentResult & ReturnsValue<IntentFile> {
        var settings = TranslationSettings.current
        if let language { settings.source = language }
        if let target { settings.target = target }
        let result = try await ScreenTranslator.translate(screenshot.data, settings: settings)
        if AppSettings.keepHistory, !result.regions.isEmpty {
            try? HistoryStore().add(result)
        }
        return .result(value: IntentFile(data: result.png, filename: "Translated-Screenshot.png", type: .png))
    }
}

extension SourceLanguage: AppEnum {
    static let typeDisplayRepresentation: TypeDisplayRepresentation = "Source Language"
    static let caseDisplayRepresentations: [SourceLanguage: DisplayRepresentation] = [
        .japanese: "Japanese",
        .chineseSimplified: "Chinese (Simplified)",
        .chineseTraditional: "Chinese (Traditional)",
        .korean: "Korean",
    ]
}

// App Intents reads these at build time, so they must be written out as literals.
extension TargetLanguage: AppEnum {
    static let typeDisplayRepresentation: TypeDisplayRepresentation = "Target Language"
    static let caseDisplayRepresentations: [TargetLanguage: DisplayRepresentation] = [
        .english: "English",
        .spanish: "Spanish",
        .french: "French",
        .german: "German",
        .italian: "Italian",
        .portuguese: "Portuguese",
        .dutch: "Dutch",
        .polish: "Polish",
        .turkish: "Turkish",
        .indonesian: "Indonesian",
        .vietnamese: "Vietnamese",
        .thai: "Thai",
    ]
}
