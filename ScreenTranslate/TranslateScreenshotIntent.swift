import AppIntents
import UniformTypeIdentifiers

/// The Shortcuts action. A shortcut on the Action Button (or Back Tap, or a Control Center
/// button) runs: Take Screenshot → Translate Screenshot → Quick Look.
struct TranslateScreenshotIntent: AppIntent {
    static let title: LocalizedStringResource = "Translate Screenshot"
    static let description = IntentDescription(
        "Finds text in a screenshot or photo, translates it on this iPhone, and returns the image with the translation drawn over the original text. Download the languages in ScreenTranslate first."
    )
    static let openAppWhenRun = false

    // Connects to the previous action's output, so Take Screenshot → Translate Screenshot is
    // linked as soon as the action is added.
    @Parameter(title: "Screenshot", supportedContentTypes: [.image], inputConnectionBehavior: .connectToPreviousIntentResult)
    var screenshot: IntentFile

    @Parameter(title: "From", description: "Leave empty to use the app's setting (automatic detection unless you changed it).")
    var language: AppLanguage?

    @Parameter(title: "To", description: "Leave empty to use the language chosen in the app.")
    var target: AppLanguage?

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
        // Say so instead of showing the screenshot back unchanged, which looks like a failure.
        guard result.regions.contains(where: { $0.source != nil }) else { throw ScreenTranslateError.noTextFound }
        if AppSettings.keepHistory, !result.regions.isEmpty {
            try? HistoryStore().add(result)
        }
        return .result(value: IntentFile(data: result.jpeg, filename: "Translated-Screenshot.jpg", type: .jpeg))
    }
}

// App Intents reads these at build time, so they must be written out as literals.
extension AppLanguage: AppEnum {
    static let typeDisplayRepresentation: TypeDisplayRepresentation = "Language"
    static let caseDisplayRepresentations: [AppLanguage: DisplayRepresentation] = [
        .english: "English",
        .spanish: "Spanish",
        .french: "French",
        .german: "German",
        .italian: "Italian",
        .portuguese: "Portuguese",
        .russian: "Russian",
        .ukrainian: "Ukrainian",
        .japanese: "Japanese",
        .chineseSimplified: "Chinese (Simplified)",
        .chineseTraditional: "Chinese (Traditional)",
        .korean: "Korean",
        .thai: "Thai",
        .vietnamese: "Vietnamese",
        .arabic: "Arabic",
        .dutch: "Dutch",
        .polish: "Polish",
        .turkish: "Turkish",
        .indonesian: "Indonesian",
        .hindi: "Hindi",
    ]
}

/// Same as Translate Screenshot, but shows the result in ScreenTranslate instead of handing an
/// image back to Shortcuts. Slower to get back from, but the result can be cropped, corrected,
/// compared with the original and read as a list.
struct TranslateScreenshotInAppIntent: AppIntent {
    static let title: LocalizedStringResource = "Translate Screenshot in App"
    static let description = IntentDescription(
        "Opens the screenshot in ScreenTranslate and translates it there, where you can select an area, correct misread text, see the original, and read a buying summary."
    )
    static let openAppWhenRun = true

    @Parameter(title: "Screenshot", supportedContentTypes: [.image], inputConnectionBehavior: .connectToPreviousIntentResult)
    var screenshot: IntentFile

    @MainActor
    func perform() async throws -> some IntentResult {
        IncomingScreenshot.shared.data = screenshot.data
        return .result()
    }
}

/// A screenshot handed to the app by the Shortcuts action, waiting to be translated on screen.
@MainActor
final class IncomingScreenshot: ObservableObject {
    static let shared = IncomingScreenshot()
    @Published var data: Data?
}
