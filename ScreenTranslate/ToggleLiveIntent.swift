import AppIntents

/// Pauses or resumes live translation without opening the app, for the Action Button or a
/// Control Center button (iOS 18 lets any Shortcuts action go there).
struct ToggleLiveIntent: AppIntent {
    static let title: LocalizedStringResource = "Pause or Resume Live Translation"
    static let description = IntentDescription("Pauses live translation if it's running, or resumes it if it's paused.")
    static let openAppWhenRun = false

    @MainActor
    func perform() async throws -> some IntentResult & ProvidesDialog {
        let live = LiveTranslator.shared
        guard live.isBroadcasting else {
            return .result(dialog: "Live translation is off. Start it from ScreenTranslate.")
        }
        live.togglePaused()
        return .result(dialog: live.isPaused ? "Live translation paused" : "Live translation on")
    }
}
