import AVFoundation
import SwiftUI

/// Shows a translation three ways: the screenshot with translations drawn over the text, the
/// untouched original, or the translations alone as a list (when the panels are too cramped to
/// read). Tapping a panel or a row shows its original text, which can be corrected and
/// translated again when the text recognizer misread it.
struct ResultView: View {
    let target: AppLanguage
    /// How long each step took, shown small under the image. Empty for history items.
    let timings: String
    /// The untranslated image. Nil for history items, which keep only the translated image.
    let originalImage: Data?
    /// Called when the user says the text was in a different language. Nil hides the picker.
    var onChangeSource: ((AppLanguage) -> Void)?
    /// Called with a cropped part of the original to translate on its own. Nil hides the button.
    var onTranslateArea: ((Data) -> Void)?

    @State private var jpeg: Data
    @State private var regions: [TranslatedRegion]
    @State private var shown: Shown = .translated
    @State private var selected: SelectedRegion?
    @State private var showCrop = false
    @State private var speaker = AVSpeechSynthesizer()
    @State private var copied = false

    enum Shown: String, CaseIterable, Identifiable {
        case translated = "Translated"
        case original = "Original"
        case text = "Text only"

        var id: String { rawValue }
    }

    struct SelectedRegion: Identifiable {
        let id: Int
    }

    init(jpeg: Data, regions: [TranslatedRegion], target: AppLanguage, timings: String = "", originalImage: Data? = nil,
         onChangeSource: ((AppLanguage) -> Void)? = nil, onTranslateArea: ((Data) -> Void)? = nil) {
        _jpeg = State(initialValue: jpeg)
        _regions = State(initialValue: regions)
        self.target = target
        self.timings = timings
        self.originalImage = originalImage
        self.onChangeSource = onChangeSource
        self.onTranslateArea = onTranslateArea
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                languageChip
                Picker("Show", selection: $shown) {
                    ForEach(Shown.allCases.filter { $0 != .original || originalImage != nil }) { option in
                        Text(option.rawValue).tag(option)
                    }
                }
                .pickerStyle(.segmented)

                if regions.contains(where: \.isUncertain) {
                    Label("(?) marks text that may have been misread, so its translation may be wrong too. Tap it to check or correct the text.", systemImage: "questionmark.circle")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                }

                if let summary {
                    summaryCard(summary)
                }
                if shown != .text {
                    imageView
                }
                if !timings.isEmpty {
                    Text(timings).font(.caption2).foregroundStyle(.secondary)
                }
                ForEach(Array(regions.enumerated()), id: \.offset) { index, region in
                    row(region, index: index)
                    Divider()
                }
            }
            .padding()
        }
        .navigationTitle("Translation")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            if originalImage != nil, onTranslateArea != nil {
                Button {
                    showCrop = true
                } label: {
                    Label("Select area", systemImage: "crop")
                }
            }
            Button(copied ? "Copied" : "Copy all") {
                UIPasteboard.general.string = regions.map(\.translated).joined(separator: "\n\n")
                copied = true
            }
            .disabled(regions.isEmpty)
            if let image = UIImage(data: jpeg) {
                ShareLink(
                    item: Image(uiImage: image),
                    preview: SharePreview("Translated image", image: Image(uiImage: image))
                )
            }
        }
        .sheet(item: $selected) { selection in
            RegionDetailView(region: regions[selection.id], target: target) { edited in
                await retranslate(selection.id, text: edited)
            }
        }
        .sheet(isPresented: $showCrop) {
            if let originalImage {
                CropView(imageData: originalImage) { cropped in
                    showCrop = false
                    onTranslateArea?(cropped)
                }
            }
        }
        .onDisappear { speaker.stopSpeaking(at: .immediate) }
    }

    /// Only in shopping mode, and only when the screen has listing terms.
    private var summary: BuyingSummary? {
        guard AppSettings.flagListingTerms else { return nil }
        return BuyingSummary.make(from: regions.filter { $0.source == .japanese }.map(\.original))
    }

    private func summaryCard(_ summary: BuyingSummary) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Buying summary").font(.headline)
            ForEach(summary.answers, id: \.question) { answer in
                VStack(alignment: .leading, spacing: 2) {
                    Text(answer.question).font(.subheadline.weight(.semibold))
                    ForEach(answer.matches, id: \.word) { match in
                        Text("\(match.tone.symbol) \(match.word): \(match.meaning)")
                            .font(.callout)
                            .foregroundStyle(match.tone == .caution ? Color.orange : match.tone == .good ? Color.green : Color.primary)
                    }
                }
            }
            if !summary.notFound.isEmpty {
                Text("Not found on this screen: \(summary.notFound.joined(separator: ", ")). Check the full listing.")
                    .font(.callout)
                    .foregroundStyle(.secondary)
            }
            Text("From the seller's own wording. It doesn't confirm the item's real condition or authenticity.")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .padding()
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(.thinMaterial, in: RoundedRectangle(cornerRadius: 12))
    }

    /// The image, with an invisible button over each piece of translated text.
    @ViewBuilder
    private var imageView: some View {
        let data = shown == .original ? (originalImage ?? jpeg) : jpeg
        if let image = UIImage(data: data) {
            Image(uiImage: image)
                .resizable()
                .scaledToFit()
                .overlay {
                    if shown == .translated {
                        GeometryReader { geometry in
                            let scale = geometry.size.width / max(image.size.width, 1)
                            ForEach(Array(regions.enumerated()), id: \.offset) { index, region in
                                Color.clear
                                    .contentShape(Rectangle())
                                    .frame(width: region.rect.width * scale, height: region.rect.height * scale)
                                    .position(x: region.rect.midX * scale, y: region.rect.midY * scale)
                                    .onTapGesture { selected = SelectedRegion(id: index) }
                                    .accessibilityLabel(region.translated)
                                    .accessibilityAddTraits(.isButton)
                            }
                        }
                    }
                }
                .clipShape(RoundedRectangle(cornerRadius: 12))
        }
    }

    private func row(_ region: TranslatedRegion, index: Int) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack(alignment: .firstTextBaseline) {
                Text((region.isUncertain ? "(?) " : "") + region.translated)
                Spacer()
                Button {
                    speak(region.translated)
                } label: {
                    Image(systemName: "speaker.wave.2")
                }
                .buttonStyle(.borderless)
                .accessibilityLabel("Read aloud")
                Button {
                    selected = SelectedRegion(id: index)
                } label: {
                    Image(systemName: "pencil")
                }
                .buttonStyle(.borderless)
                .accessibilityLabel("Check or correct the original text")
            }
            ForEach(region.notes, id: \.self) { note in
                Text(note)
                    .font(.callout)
                    .foregroundStyle(note.hasPrefix("⚠") ? Color.orange : note.hasPrefix("✓") ? Color.green : Color.secondary)
            }
            Text(region.original).font(.footnote).foregroundStyle(.secondary)
        }
        .textSelection(.enabled)
    }

    /// Translates corrected text again, and redraws the image with it when the original is at hand.
    private func retranslate(_ index: Int, text: String) async {
        let old = regions[index]
        let settings = TranslationSettings.current
        let language = LanguageDetector.sourceLanguage(of: text, source: old.source ?? settings.source, target: target)
        var translated = text
        if let language, let result = try? await Translator.translate([text], from: language, to: target).first {
            translated = result
        }
        let rates = await ScreenTranslator.priceRates(for: [(text, language)], settings: settings)
        let (notes, isWarning) = ScreenTranslator.annotations(for: text, language: language, settings: settings, rates: rates)
        regions[index] = TranslatedRegion(
            original: text, translated: translated, source: language, rect: old.rect,
            notes: notes, isWarning: isWarning, lineHeight: old.lineHeight
        )
        if let originalImage, let image = ScreenTranslator.decode(originalImage),
           let redrawn = OverlayRenderer.render(image: image, regions: regions, obstacles: regions.map(\.rect), options: settings.overlay, summary: summary?.lines ?? []) {
            jpeg = redrawn
        }
    }

    /// "Japanese → English", with a menu to say the text was really in another language.
    @ViewBuilder
    private var languageChip: some View {
        let sources = Array(Set(regions.compactMap(\.source))).sorted { $0.displayName < $1.displayName }
        let label = "\(sources.isEmpty ? "No text found" : sources.map(\.displayName).joined(separator: ", ")) → \(target.displayName)"
        if let onChangeSource {
            Menu {
                Section("Wrong language? Translate from:") {
                    ForEach(AppLanguage.readable.filter { $0 != target }) { language in
                        Button(language.displayName) { onChangeSource(language) }
                    }
                }
            } label: {
                Label(label, systemImage: "character.bubble")
                    .font(.subheadline)
                    .padding(.horizontal, 12)
                    .padding(.vertical, 6)
                    .background(.thinMaterial, in: Capsule())
            }
        } else {
            Label(label, systemImage: "character.bubble").font(.subheadline).foregroundStyle(.secondary)
        }
    }

    private func speak(_ text: String) {
        speaker.stopSpeaking(at: .immediate)
        let utterance = AVSpeechUtterance(string: text)
        // Speech voices use region codes rather than script codes for Chinese.
        let voiceLanguage = [AppLanguage.chineseSimplified: "zh-CN", .chineseTraditional: "zh-TW"][target] ?? target.rawValue
        utterance.voice = AVSpeechSynthesisVoice(language: voiceLanguage)
        speaker.speak(utterance)
    }
}


/// One piece of text: what was read, its translation, and the notes, with the reading editable.
struct RegionDetailView: View {
    let region: TranslatedRegion
    let target: AppLanguage
    let onRetranslate: (String) async -> Void

    @State private var edited: String
    @State private var working = false
    @Environment(\.dismiss) private var dismiss

    init(region: TranslatedRegion, target: AppLanguage, onRetranslate: @escaping (String) async -> Void) {
        self.region = region
        self.target = target
        self.onRetranslate = onRetranslate
        _edited = State(initialValue: region.original)
    }

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    TextField("Original text", text: $edited, axis: .vertical)
                } header: {
                    Text("Original, as read from the image")
                } footer: {
                    if region.isUncertain {
                        Text("This text may have been misread. Compare it with the image, fix it, and translate again.")
                    } else {
                        Text("If this doesn't match the image, fix it and translate again.")
                    }
                }
                Section("Translation") {
                    Text(region.translated).textSelection(.enabled)
                }
                if !region.notes.isEmpty {
                    Section {
                        ForEach(region.notes, id: \.self) { Text($0) }
                    } header: {
                        Text("Notes")
                    } footer: {
                        Text("Notes explain the words in the original. They describe what the seller wrote, not whether it's true.")
                    }
                }
                Section {
                    Button(working ? "Translating…" : "Translate edited text") {
                        working = true
                        Task {
                            await onRetranslate(edited.trimmingCharacters(in: .whitespacesAndNewlines))
                            working = false
                            dismiss()
                        }
                    }
                    .disabled(working || edited.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || edited == region.original)
                }
            }
            .navigationTitle("Text")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar { Button("Done") { dismiss() } }
        }
    }
}

/// Lets the user drag a rectangle over the original image and translate only that part.
struct CropView: View {
    let imageData: Data
    let onTranslate: (Data) -> Void

    @State private var start: CGPoint?
    @State private var end: CGPoint?
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            GeometryReader { geometry in
                if let image = ScreenTranslator.decode(imageData) {
                    let imageSize = CGSize(width: image.width, height: image.height)
                    let fitted = AVMakeRect(aspectRatio: imageSize, insideRect: CGRect(origin: .zero, size: geometry.size))
                    ZStack(alignment: .topLeading) {
                        Image(decorative: image, scale: 1)
                            .resizable()
                            .frame(width: fitted.width, height: fitted.height)
                            .offset(x: fitted.minX, y: fitted.minY)
                        if let selection = selection(in: fitted) {
                            Rectangle()
                                .path(in: selection)
                                .stroke(Color.accentColor, lineWidth: 3)
                            Rectangle()
                                .path(in: selection)
                                .fill(Color.accentColor.opacity(0.15))
                        }
                    }
                    .contentShape(Rectangle())
                    .gesture(
                        DragGesture(minimumDistance: 0)
                            .onChanged { value in
                                if start == nil || value.translation == .zero { start = value.startLocation }
                                end = value.location
                            }
                    )
                    .toolbar {
                        ToolbarItem(placement: .cancellationAction) {
                            Button("Cancel") { dismiss() }
                        }
                        ToolbarItem(placement: .confirmationAction) {
                            Button("Translate") {
                                guard let selection = selection(in: fitted) else { return }
                                let scale = imageSize.width / fitted.width
                                let crop = CGRect(
                                    x: (selection.minX - fitted.minX) * scale,
                                    y: (selection.minY - fitted.minY) * scale,
                                    width: selection.width * scale,
                                    height: selection.height * scale
                                ).integral
                                if let cropped = image.cropping(to: crop),
                                   let data = UIImage(cgImage: cropped).jpegData(compressionQuality: 0.95) {
                                    onTranslate(data)
                                }
                            }
                            .disabled((selection(in: fitted)?.width ?? 0) < 20)
                        }
                    }
                }
            }
            .navigationTitle("Drag over the text")
            .navigationBarTitleDisplayMode(.inline)
        }
    }

    /// The dragged rectangle, kept inside the image.
    private func selection(in fitted: CGRect) -> CGRect? {
        guard let start, let end else { return nil }
        let rect = CGRect(x: min(start.x, end.x), y: min(start.y, end.y), width: abs(end.x - start.x), height: abs(end.y - start.y))
        let clipped = rect.intersection(fitted)
        return clipped.isNull || clipped.width < 1 || clipped.height < 1 ? nil : clipped
    }
}

struct HistoryView: View {
    @State private var items: [HistoryItem] = []
    private let store = HistoryStore()

    var body: some View {
        List {
            if items.isEmpty {
                Text("No saved translations. Turn on Keep history to save them on this iPhone.")
                    .foregroundStyle(.secondary)
            }
            ForEach(items) { item in
                NavigationLink {
                    if let jpeg = store.imageData(for: item) {
                        ResultView(jpeg: jpeg, regions: item.regions, target: item.target)
                    }
                } label: {
                    VStack(alignment: .leading) {
                        Text(item.regions.first?.translated ?? "Translation").lineLimit(2)
                        Text("To \(item.target.displayName) · \(item.date.formatted(date: .abbreviated, time: .shortened))")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
            }
        }
        .navigationTitle("History")
        .toolbar {
            // Always shown: it also empties the cache of remembered translations.
            Button("Clear", role: .destructive) {
                try? store.clear()
                TranslationCache.clearAll()
                items = []
            }
        }
        .onAppear { items = store.load() }
    }
}
