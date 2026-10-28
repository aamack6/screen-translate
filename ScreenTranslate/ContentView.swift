import PhotosUI
import SwiftUI
import Translation

struct ContentView: View {
    @AppStorage(SettingsKey.sourceLanguage) private var sourceSetting = autoDetectSetting
    @AppStorage(SettingsKey.targetLanguage) private var target: AppLanguage = AppSettings.deviceLanguage
    @AppStorage(SettingsKey.convertPrices) private var convertPrices = false
    @AppStorage(SettingsKey.displayCurrency) private var currency = DisplayCurrency.deviceDefault
    @AppStorage(SettingsKey.extraCost) private var extraCost = 0.0
    @AppStorage(SettingsKey.flagListingTerms) private var flagListingTerms = true
    @AppStorage(SettingsKey.darkPanels) private var darkPanels = false
    @AppStorage(SettingsKey.appendFullText) private var appendFullText = false
    @AppStorage(SettingsKey.keepHistory) private var keepHistory = false
    @AppStorage(SettingsKey.onlineEngine) private var onlineEngine: OnlineEngine = .off
    @State private var apiKey = ""
    @State private var trigger: Trigger = .floatingDot
    @State private var keyCheck: String?

    /// With automatic detection, the language whose download the Language section shows.
    @State private var downloadSource: AppLanguage = .japanese
    @State private var status: LanguageStatus?
    @State private var translationConfig: TranslationSession.Configuration?
    @State private var downloadError: String?
    @State private var ratesUpdated: Date?

    @State private var pickerItem: PhotosPickerItem?
    @State private var joinItems: [PhotosPickerItem] = []
    @State private var showCamera = false
    @State private var showLiveCamera = false
    @State private var isTranslating = false
    @State private var shownResult: ShownResult?
    @State private var translateError: String?

    @StateObject private var store = Store.shared
    @State private var remainingFree = Usage.remainingToday

    @Environment(\.openURL) private var openURL
    @Environment(\.scenePhase) private var scenePhase

    private var source: AppLanguage? { AppLanguage(rawValue: sourceSetting) }
    /// The pair whose download status is shown: the chosen source, or with automatic detection,
    /// the language picked in the download row.
    private var statusSource: AppLanguage { source ?? downloadSource }

    var body: some View {
        NavigationStack {
            Form {
                translateSection
                liveSection
                proSection
                languageSection
                engineSection
                setupSection
                pricesSection
                optionsSection
                Section {
                    NavigationLink("History") { HistoryView() }
                } footer: {
                    Text("Translation happens on this iPhone. No account, no API key, and images never leave your phone. Screenshots aren't saved to Photos.")
                }
            }
            .navigationTitle("ScreenTranslate")
            .task(id: "\(statusSource.rawValue)>\(target.rawValue)") { await refreshStatus() }
            .translationTask(translationConfig) { session in
                do {
                    try await session.prepareTranslation()
                    downloadError = nil
                } catch {
                    downloadError = error.localizedDescription
                }
                await refreshStatus()
            }
            .navigationDestination(item: $shownResult) { result in
                ResultView(jpeg: result.jpeg, regions: result.regions, target: result.target, timings: result.timings) { language in
                    Task { await retranslate(result, from: language) }
                }
            }
            .task { await store.load() }
            .task { await Translator.warmUpLikelyPair() }
            .onChange(of: "\(sourceSetting)>\(target.rawValue)") { LiveTranslator.shared.writeConfig() }
            .onChange(of: scenePhase) { _, phase in
                // The Shortcuts action may have used free translations while the app was closed.
                if phase == .active { remainingFree = Usage.remainingToday }
            }
            .fullScreenCover(isPresented: $showLiveCamera) {
                LiveCameraView()
            }
            .fullScreenCover(isPresented: $showCamera) {
                CameraPicker { data in
                    showCamera = false
                    if let data {
                        Task { await translate(data, skipStatusBar: false) }
                    }
                }
                .ignoresSafeArea()
            }
        }
    }

    // MARK: - Sections

    private var translateSection: some View {
        Section {
            PhotosPicker(selection: $pickerItem, matching: .images) {
                Label("Translate a photo or screenshot", systemImage: "photo.on.rectangle")
            }
            PhotosPicker(selection: $joinItems, maxSelectionCount: 8, selectionBehavior: .ordered, matching: .images) {
                Label("Join screenshots into one page", systemImage: "rectangle.stack")
            }
            if UIImagePickerController.isSourceTypeAvailable(.camera) {
                Button {
                    showCamera = true
                } label: {
                    Label("Translate a photo from the camera", systemImage: "camera")
                }
                Button {
                    showLiveCamera = true
                } label: {
                    Label("Live camera", systemImage: "camera.viewfinder")
                }
            }
            NavigationLink {
                BrowserView()
            } label: {
                Label("Translate a website", systemImage: "safari")
            }
            if isTranslating {
                ProgressView("Reading and translating…")
            }
            if let translateError {
                Text(translateError).font(.footnote).foregroundStyle(.red)
            }
        } header: {
            Text("Translate")
        } footer: {
            Text("Menus, signs, documents, games, chats, shopping sites: anything with text. For a long page, take a screenshot, scroll a bit, take another, and so on, then join them: pick them top to bottom and they become one scrollable translation. For other apps, set up the one-press shortcut below.")
        }
        .disabled(isTranslating)
        .onChange(of: pickerItem) { _, item in
            guard let item else { return }
            Task {
                defer { pickerItem = nil }
                guard let data = try? await item.loadTransferable(type: Data.self) else {
                    translateError = ScreenTranslateError.unreadableImage.localizedDescription
                    return
                }
                await translate(data, skipStatusBar: true)
            }
        }
        .onChange(of: joinItems) { _, items in
            guard !items.isEmpty else { return }
            Task {
                defer { joinItems = [] }
                var screenshots: [Data] = []
                for item in items {
                    guard let data = try? await item.loadTransferable(type: Data.self) else {
                        translateError = ScreenTranslateError.unreadableImage.localizedDescription
                        return
                    }
                    screenshots.append(data)
                }
                await translateJoined(screenshots)
            }
        }
    }

    private var liveSection: some View {
        Section {
            NavigationLink {
                LiveView()
            } label: {
                Label("Live mode", systemImage: "pip")
            }
        } footer: {
            Text("A floating window that keeps translating your screen in any app, as you scroll.")
        }
    }

    @ViewBuilder
    private var proSection: some View {
        Section {
            if store.isPro {
                Label("Pro: unlimited translations and live mode", systemImage: "checkmark.seal.fill").foregroundStyle(.green)
            } else {
                Text("\(remainingFree) of \(Usage.freeTranslationsPerDay) free translations left today")
                if let product = store.proProduct {
                    Button("Unlock unlimited, one time: \(product.displayPrice)") {
                        Task { await store.buyPro() }
                    }
                }
                Button("Restore purchases") {
                    Task { await store.restore() }
                }
                if let error = store.purchaseError {
                    Text(error).font(.footnote).foregroundStyle(.red)
                }
            }
        } header: {
            Text("ScreenTranslate Pro")
        } footer: {
            if !store.isPro {
                Text("One payment, yours forever. No ads, no subscription, no coins.")
            }
        }
    }

    private var languageSection: some View {
        Section {
            Picker("From", selection: $sourceSetting) {
                Text("Detect automatically").tag(autoDetectSetting)
                ForEach(AppLanguage.readable) { language in
                    Text(language.displayName).tag(language.rawValue)
                }
            }
            Picker("To", selection: $target) {
                ForEach(AppLanguage.allCases) { language in
                    Text(language.displayName).tag(language)
                }
            }
            if source == nil {
                Picker("Download for", selection: $downloadSource) {
                    ForEach(AppLanguage.readable.filter { $0 != target }) { language in
                        Text(language.displayName).tag(language)
                    }
                }
            }
            statusRow
            if status == .needsDownload {
                Button("Download \(statusSource.displayName) → \(target.displayName)") { downloadLanguages() }
            }
            if let downloadError {
                Text(downloadError).font(.footnote).foregroundStyle(.red)
            }
        } header: {
            Text("Languages")
        } footer: {
            Text(source == nil
                ? "Each language is detected on its own, so mixed screens work. Download each language you expect to read once; after that, translation works offline."
                : "Approve Apple's download once, and after that translation works offline.")
        }
    }

    @ViewBuilder
    private var statusRow: some View {
        if statusSource == target {
            Label("Pick two different languages", systemImage: "exclamationmark.triangle").foregroundStyle(.orange)
        } else {
            switch status {
            case nil:
                Label("Checking languages…", systemImage: "hourglass")
            case .installed:
                Label("\(statusSource.displayName) is ready", systemImage: "checkmark.circle.fill").foregroundStyle(.green)
            case .needsDownload:
                Label("Download needed", systemImage: "arrow.down.circle").foregroundStyle(.orange)
            case .unsupported:
                Label("Not available on this device", systemImage: "xmark.octagon").foregroundStyle(.red)
            }
        }
    }

    private var setupSection: some View {
        Section {
            VStack(alignment: .leading, spacing: 8) {
                Text("1. In Shortcuts, create a shortcut called Screen Translate.")
                Text("2. Add Take Screenshot.")
                Text("3. Add Translate Screenshot, with the screenshot from step 2.")
                Text("4. Add Quick Look, showing the result of step 3.")
            }
            .font(.callout)
            Picker("Start it with", selection: $trigger) {
                ForEach(Trigger.allCases) { trigger in
                    Text(trigger.name).tag(trigger)
                }
            }
            VStack(alignment: .leading, spacing: 8) {
                ForEach(Array(trigger.steps.enumerated()), id: \.offset) { index, step in
                    Text("\(index + 5). \(step)")
                }
            }
            .font(.callout)
            Button("Open Shortcuts") {
                if let url = URL(string: "shortcuts://") { openURL(url) }
            }
            if let link = AppLinks.readyMadeShortcut {
                Link("Add the ready-made shortcut", destination: link)
            }
        } header: {
            Text("Translate any app in one press")
        } footer: {
            Text("Then press it while looking at any app. Close Quick Look to go back.")
        }
    }

    /// Ways iOS lets a shortcut be started from inside any app.
    enum Trigger: String, CaseIterable, Identifiable {
        case floatingDot, actionButton, backTap, controlCenter

        var id: String { rawValue }

        var name: String {
            switch self {
            case .floatingDot: return "Floating button"
            case .actionButton: return "Action Button"
            case .backTap: return "Back Tap"
            case .controlCenter: return "Control Center"
            }
        }

        var steps: [String] {
            switch self {
            case .floatingDot: return [
                "Open Settings › Accessibility › Touch › AssistiveTouch and turn it on. A small button floats on the screen; drag it anywhere.",
                "Under Custom Actions, set Single-Tap to Screen Translate (shortcuts are near the bottom of the list).",
                "Optional: lower Idle Opacity so the button almost disappears when you're not using it. It never shows in screenshots.",
            ]
            case .actionButton: return [
                "Open Settings › Action Button, swipe to Shortcut, and choose Screen Translate.",
            ]
            case .backTap: return [
                "Open Settings › Accessibility › Touch › Back Tap › Double Tap and choose Screen Translate. Then tap the back of the iPhone twice.",
            ]
            case .controlCenter: return [
                "Open Control Center, press and hold, tap Add a Control, choose Shortcut, and pick Screen Translate.",
            ]
            }
        }
    }

    private var pricesSection: some View {
        Section {
            Toggle("Convert prices", isOn: $convertPrices)
            if convertPrices {
                Picker("Show prices in", selection: $currency) {
                    ForEach(DisplayCurrency.codes, id: \.self) { code in
                        Text(code).tag(code)
                    }
                }
                LabeledContent("Extra cost per item (\(currency))") {
                    TextField("0", value: $extraCost, format: .number)
                        .keyboardType(.decimalPad)
                        .multilineTextAlignment(.trailing)
                        .frame(maxWidth: 120)
                }
            }
            if source == nil || source == .japanese {
                Toggle("Explain Japanese shopping terms", isOn: $flagListingTerms)
            }
        } header: {
            Text("Prices and shopping")
        } footer: {
            VStack(alignment: .leading, spacing: 6) {
                if convertPrices {
                    Text("Prices like $19.99, 12,50 €, ¥12,800, 1万2000円 or ₹499 get an estimate in \(currency) underneath. An extra cost, such as shipping or a proxy-service fee, adds a \"with fees\" total.")
                    if let ratesUpdated {
                        Text("Rates updated \(ratesUpdated.formatted(date: .abbreviated, time: .shortened)). [Rates by Exchange Rate API](https://www.exchangerate-api.com)")
                    } else {
                        Text("Rates download once and are reused for 12 hours. [Rates by Exchange Rate API](https://www.exchangerate-api.com)")
                    }
                }
                if (source == nil || source == .japanese), flagListingTerms {
                    Text("Listing words like ジャンク (junk), 傷あり (scratched) or 海外版 (overseas edition) get a plain-English note, and the panel gets an orange border.")
                }
            }
        }
        .task(id: "\(convertPrices)\(currency)") {
            guard convertPrices else { return }
            // Warm the cache for the most common case so the first translation is instant.
            let base = currency == "USD" ? "EUR" : "USD"
            _ = await ExchangeRates.rate(from: base, to: currency)
            ratesUpdated = ExchangeRates.lastUpdated(for: base)
        }
    }

    private var engineSection: some View {
        Section {
            Picker("Engine", selection: $onlineEngine) {
                ForEach(OnlineEngine.allCases) { engine in
                    Text(engine.displayName).tag(engine)
                }
            }
            if onlineEngine != .off {
                SecureField(onlineEngine == .deepL ? "DeepL API key" : "Google Cloud API key", text: $apiKey)
                    .textInputAutocapitalization(.never)
                    .autocorrectionDisabled()
                    .onSubmit(saveKey)
                Button("Save and test key", action: saveKey)
                    .disabled(apiKey.isEmpty)
                if let keyCheck {
                    Text(keyCheck).font(.footnote).foregroundStyle(keyCheck.hasPrefix("✓") ? Color.green : Color.red)
                }
            }
        } header: {
            Text("Translation engine")
        } footer: {
            if onlineEngine == .off {
                Text("Apple's engine works offline and keeps everything on this iPhone, but takes about two seconds for new text. An online engine answers in a fraction of a second.")
            } else if !store.isPro {
                Text("Online engines are part of Pro.")
            } else {
                Text("Uses your own key, so you pay the service directly (both have a free monthly allowance). Only the text read from the screen is sent, never the image. Without a connection, Apple's engine is used.")
            }
        }
        .onAppear { apiKey = APIKeyStore.key(for: onlineEngine) ?? "" }
        .onChange(of: onlineEngine) { _, engine in
            apiKey = APIKeyStore.key(for: engine) ?? ""
            keyCheck = nil
        }
    }

    private func saveKey() {
        let engine = onlineEngine
        APIKeyStore.setKey(apiKey, for: engine)
        keyCheck = "Testing…"
        Task {
            if let error = await OnlineTranslator.test(engine) {
                keyCheck = error
            } else {
                keyCheck = "✓ Key works"
            }
        }
    }

    private var optionsSection: some View {
        Section("Options") {
            NavigationLink("My word list") { WordListView() }
            Toggle("Dark translation panels", isOn: $darkPanels)
            Toggle("List all translations under the image", isOn: $appendFullText)
            Toggle("Keep history on this iPhone", isOn: $keepHistory)
        }
    }

    // MARK: - Actions

    private func refreshStatus() async {
        status = nil
        guard statusSource != target else { return }
        status = await Translator.status(from: statusSource, to: target)
    }

    private func downloadLanguages() {
        if translationConfig?.source == statusSource.localeLanguage, translationConfig?.target == target.localeLanguage {
            translationConfig?.invalidate()
        } else {
            translationConfig = TranslationSession.Configuration(source: statusSource.localeLanguage, target: target.localeLanguage)
        }
    }

    private func translate(_ data: Data, skipStatusBar: Bool) async {
        var settings = TranslationSettings.current
        settings.skipStatusBar = skipStatusBar
        await run(data, settings: settings)
    }

    /// Joins screenshots taken while scrolling into one page and translates it. A retry then
    /// works on the joined page like on any other image.
    private func translateJoined(_ screenshots: [Data]) async {
        var settings = TranslationSettings.current
        settings.skipStatusBar = false
        await run(settings: settings) {
            try await ScreenTranslator.translateJoined(screenshots, settings: settings)
        }
    }

    /// Translates the same image again from a language the user picked, when detection got it wrong.
    /// A retry doesn't use up a free translation.
    private func retranslate(_ result: ShownResult, from language: AppLanguage) async {
        var settings = TranslationSettings.current
        settings.source = language
        settings.skipStatusBar = result.skipStatusBar
        settings.countsTowardAllowance = false
        await run(result.imageData, settings: settings)
    }

    private func run(_ data: Data, settings: TranslationSettings) async {
        await run(settings: settings) {
            (try await ScreenTranslator.translate(data, settings: settings), data)
        }
    }

    /// - Parameter perform: translates, returning the result and the image it was made from.
    private func run(settings: TranslationSettings, perform: () async throws -> (RenderedTranslation, Data)) async {
        isTranslating = true
        translateError = nil
        defer {
            isTranslating = false
            remainingFree = Usage.remainingToday
        }
        do {
            let (rendered, data) = try await perform()
            if rendered.regions.isEmpty {
                translateError = "No text to translate was found in that image."
            }
            if keepHistory, !rendered.regions.isEmpty {
                try? HistoryStore().add(rendered)
            }
            shownResult = ShownResult(
                jpeg: rendered.jpeg,
                timings: rendered.timings,
                regions: rendered.regions,
                target: rendered.target,
                imageData: data,
                skipStatusBar: settings.skipStatusBar
            )
        } catch let error as ScreenTranslateError {
            translateError = error.localizedDescription
            // Point the download row at the missing language so one tap fixes it.
            if let pair = error.missingPair, source == nil {
                downloadSource = pair.0
            }
        } catch {
            translateError = error.localizedDescription
        }
    }
}

/// A translation to open from the Translate section, usable with `navigationDestination(item:)`.
struct ShownResult: Hashable {
    let id = UUID()
    let jpeg: Data
    let regions: [TranslatedRegion]
    let target: AppLanguage
    /// The untranslated image, kept so the user can retry with another source language.
    let imageData: Data
    let skipStatusBar: Bool
    let timings: String

    static func == (lhs: ShownResult, rhs: ShownResult) -> Bool { lhs.id == rhs.id }
    func hash(into hasher: inout Hasher) { hasher.combine(id) }
}

/// Takes one photo with the camera and hands it back as JPEG data (nil if cancelled).
struct CameraPicker: UIViewControllerRepresentable {
    let onFinish: (Data?) -> Void

    func makeUIViewController(context: Context) -> UIImagePickerController {
        let picker = UIImagePickerController()
        picker.sourceType = .camera
        picker.delegate = context.coordinator
        return picker
    }

    func updateUIViewController(_ controller: UIImagePickerController, context: Context) {}

    func makeCoordinator() -> Coordinator { Coordinator(onFinish: onFinish) }

    final class Coordinator: NSObject, UIImagePickerControllerDelegate, UINavigationControllerDelegate {
        let onFinish: (Data?) -> Void

        init(onFinish: @escaping (Data?) -> Void) { self.onFinish = onFinish }

        func imagePickerController(_ picker: UIImagePickerController, didFinishPickingMediaWithInfo info: [UIImagePickerController.InfoKey: Any]) {
            let image = info[.originalImage] as? UIImage
            onFinish(image?.jpegData(compressionQuality: 0.9))
        }

        func imagePickerControllerDidCancel(_ picker: UIImagePickerController) {
            onFinish(nil)
        }
    }
}

enum AppLinks {
    /// iCloud link to a ready-made "Screen Translate" shortcut. Fill this in after sharing the
    /// shortcut from the Shortcuts app (Share › Copy iCloud Link).
    static let readyMadeShortcut: URL? = nil
}
