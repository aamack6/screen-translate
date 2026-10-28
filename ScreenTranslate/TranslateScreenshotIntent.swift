import AppIntents
import UniformTypeIdentifiers

/// The Shortcuts action. A shortcut on the Action Button runs:
/// Take Screenshot → Translate Screenshot → Quick Look.
struct TranslateScreenshotIntent: AppIntent {
    static let title: LocalizedStringResource = "Translate Screenshot"
    static let description = IntentDescription(
        "Finds text in a screenshot, translates it to English on this iPhone, and returns the screenshot with the English drawn over the original text. Download the languages in ScreenTranslate first."
    )
    static let openAppWhenRun = false

    @Parameter(title: "Screenshot", supportedContentTypes: [.image])
    var screenshot: IntentFile

    @Parameter(title: "From", description: "Leave empty to use the language chosen in the app.")
    var language: SourceLanguage?

    static var parameterSummary: some ParameterSummary {
        Summary("Translate \(\.$screenshot) to English") {
            \.$language
        }
    }

    func perform() async throws -> some IntentResult & ReturnsValue<IntentFile> {
        let result = try await ScreenTranslator.translate(
            screenshot.data,
            source: language ?? AppSettings.sourceLanguage,
            options: AppSettings.overlayOptions
        )
        if AppSettings.keepHistory, !result.regions.isEmpty {
            try? HistoryStore().add(result)
        }
        return .result(value: IntentFile(data: result.png, filename: "Translated-Screenshot.png", type: .png))
    }
}

extension SourceLanguage: AppEnum {
    static let typeDisplayRepresentation: TypeDisplayRepresentation = "Language"
    static let caseDisplayRepresentations: [SourceLanguage: DisplayRepresentation] = [
        .japanese: "Japanese",
        .chineseSimplified: "Chinese (Simplified)",
        .chineseTraditional: "Chinese (Traditional)",
        .korean: "Korean",
    ]
}
