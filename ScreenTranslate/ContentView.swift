import PhotosUI
import SwiftUI
import Translation

struct ContentView: View {
    @AppStorage(SettingsKey.sourceLanguage) private var source: SourceLanguage = .japanese
    @AppStorage(SettingsKey.targetLanguage) private var target: TargetLanguage = .english
    @AppStorage(SettingsKey.convertPrices) private var convertPrices = false
    @AppStorage(SettingsKey.displayCurrency) private var currency: DisplayCurrency = .usd
    @AppStorage(SettingsKey.extraCost) private var extraCost = 0.0
    @AppStorage(SettingsKey.flagListingTerms) private var flagListingTerms = true
    @AppStorage(SettingsKey.darkPanels) private var darkPanels = false
    @AppStorage(SettingsKey.appendFullText) private var appendFullText = false
    @AppStorage(SettingsKey.keepHistory) private var keepHistory = false

    @State private var status: LanguageStatus?
    @State private var translationConfig: TranslationSession.Configuration?
    @State private var downloadError: String?
    @State private var ratesUpdated: Date?

    @State private var pickerItem: PhotosPickerItem?
    @State private var isTranslating = false
    @State private var shownResult: ShownResult?
    @State private var testError: String?

    @Environment(\.openURL) private var openURL

    var body: some View {
        NavigationStack {
            Form {
                languageSection
                setupSection
                shoppingSection
                optionsSection
                testSection
                Section {
                    NavigationLink("History") { HistoryView() }
                } footer: {
                    Text("Everything happens on this iPhone. No account, no subscription, no API key. Screenshots aren't saved to Photos.")
                }
            }
            .navigationTitle("ScreenTranslate")
            .task(id: "\(source.rawValue)>\(target.rawValue)") { await refreshStatus() }
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
                ResultView(png: result.png, regions: result.regions)
            }
        }
    }

    // MARK: - Sections

    private var languageSection: some View {
        Section {
            Picker("Translate from", selection: $source) {
                ForEach(SourceLanguage.allCases) { language in
                    Text(language.displayName).tag(language)
                }
            }
            Picker("Translate to", selection: $target) {
                ForEach(TargetLanguage.allCases) { language in
                    Text(language.displayName).tag(language)
                }
            }
            statusRow
            if status == .needsDownload {
                Button("Download languages") { downloadLanguages() }
            }
            if let downloadError {
                Text(downloadError).font(.footnote).foregroundStyle(.red)
            }
        } header: {
            Text("Language")
        } footer: {
            Text("Approve Apple's language download once for each pair, and after that translation works offline.")
        }
    }

    @ViewBuilder
    private var statusRow: some View {
        switch status {
        case nil:
            Label("Checking languages…", systemImage: "hourglass")
        case .installed:
            Label("Ready to translate", systemImage: "checkmark.circle.fill").foregroundStyle(.green)
        case .needsDownload:
            Label("Download needed", systemImage: "arrow.down.circle").foregroundStyle(.orange)
        case .unsupported:
            Label("Not available on this device", systemImage: "xmark.octagon").foregroundStyle(.red)
        }
    }

    private var setupSection: some View {
        Section {
            VStack(alignment: .leading, spacing: 8) {
                Text("1. In Shortcuts, create a shortcut called Screen Translate.")
                Text("2. Add Take Screenshot.")
                Text("3. Add Translate Screenshot, with the screenshot from step 2.")
                Text("4. Add Quick Look, showing the result of step 3.")
                Text("5. In Settings › Action Button, choose Shortcut › Screen Translate.")
            }
            .font(.callout)
            Button("Open Shortcuts") {
                if let url = URL(string: "shortcuts://") { openURL(url) }
            }
            if let link = AppLinks.readyMadeShortcut {
                Link("Add the ready-made shortcut", destination: link)
            }
        } header: {
            Text("Set up the Action Button")
        } footer: {
            Text("Then press the Action Button while looking at any app. Close Quick Look to go back.")
        }
    }

    private var shoppingSection: some View {
        Section {
            Toggle("Convert prices", isOn: $convertPrices)
            if convertPrices {
                Picker("Show prices in", selection: $currency) {
                    ForEach(DisplayCurrency.allCases) { currency in
                        Text(currency.rawValue).tag(currency)
                    }
                }
                LabeledContent("Extra costs per item (\(source.homeCurrency))") {
                    TextField("0", value: $extraCost, format: .number)
                        .keyboardType(.decimalPad)
                        .multilineTextAlignment(.trailing)
                        .frame(maxWidth: 120)
                }
            }
            if source == .japanese {
                Toggle("Explain condition words", isOn: $flagListingTerms)
            }
        } header: {
            Text("Shopping")
        } footer: {
            VStack(alignment: .leading, spacing: 6) {
                if convertPrices {
                    Text("Prices like ¥12,800 or 1万2000円 get an estimate in \(currency.rawValue) underneath. Extra costs, such as a proxy service fee or domestic shipping, are added to each price for a \"with fees\" total.")
                    if let ratesUpdated {
                        Text("Rates updated \(ratesUpdated.formatted(date: .abbreviated, time: .shortened)). [Rates by Exchange Rate API](https://www.exchangerate-api.com)")
                    } else {
                        Text("Rates download once and are reused for 12 hours. [Rates by Exchange Rate API](https://www.exchangerate-api.com)")
                    }
                }
                if source == .japanese, flagListingTerms {
                    Text("Words like ジャンク (junk), 傷あり (scratched) or 海外版 (overseas edition) get a plain-English note, and the panel gets an orange border.")
                }
            }
        }
        .task(id: "\(convertPrices)\(source.rawValue)\(currency.rawValue)") {
            guard convertPrices else { return }
            _ = await ExchangeRates.rate(from: source.homeCurrency, to: currency.rawValue)
            ratesUpdated = ExchangeRates.lastUpdated(for: source.homeCurrency)
        }
    }

    private var optionsSection: some View {
        Section("Options") {
            Toggle("Dark translation panels", isOn: $darkPanels)
            Toggle("List all translations under the image", isOn: $appendFullText)
            Toggle("Keep history on this iPhone", isOn: $keepHistory)
        }
    }

    private var testSection: some View {
        Section {
            PhotosPicker(selection: $pickerItem, matching: .screenshots) {
                Label("Choose a screenshot to test", systemImage: "photo.on.rectangle")
            }
            .disabled(isTranslating)
            if isTranslating {
                ProgressView("Reading and translating…")
            }
            if let testError {
                Text(testError).font(.footnote).foregroundStyle(.red)
            }
        } header: {
            Text("Try it")
        }
        .onChange(of: pickerItem) { _, item in
            guard let item else { return }
            Task { await translatePicked(item) }
        }
    }

    // MARK: - Actions

    private func refreshStatus() async {
        status = nil
        status = await Translator.status(from: source, to: target)
    }

    private func downloadLanguages() {
        if translationConfig?.source == source.localeLanguage, translationConfig?.target == target.localeLanguage {
            translationConfig?.invalidate()
        } else {
            translationConfig = TranslationSession.Configuration(source: source.localeLanguage, target: target.localeLanguage)
        }
    }

    private func translatePicked(_ item: PhotosPickerItem) async {
        isTranslating = true
        testError = nil
        defer {
            isTranslating = false
            pickerItem = nil
        }
        do {
            guard let data = try await item.loadTransferable(type: Data.self) else {
                throw ScreenTranslateError.unreadableImage
            }
            let rendered = try await ScreenTranslator.translate(data, settings: .current)
            if rendered.regions.isEmpty {
                testError = "No \(source.displayName) text was found in that screenshot."
            }
            if keepHistory, !rendered.regions.isEmpty {
                try? HistoryStore().add(rendered)
            }
            shownResult = ShownResult(png: rendered.png, regions: rendered.regions)
        } catch {
            testError = error.localizedDescription
        }
    }
}

/// A translation to open from the test section, usable with `navigationDestination(item:)`.
struct ShownResult: Hashable {
    let id = UUID()
    let png: Data
    let regions: [TranslatedRegion]

    static func == (lhs: ShownResult, rhs: ShownResult) -> Bool { lhs.id == rhs.id }
    func hash(into hasher: inout Hasher) { hasher.combine(id) }
}

enum AppLinks {
    /// iCloud link to a ready-made "Screen Translate" shortcut. Fill this in after sharing the
    /// shortcut from the Shortcuts app (Share › Copy iCloud Link).
    static let readyMadeShortcut: URL? = nil
}
