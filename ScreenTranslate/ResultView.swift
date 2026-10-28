import AVFoundation
import SwiftUI

/// Shows a translated image with its translations as selectable text, each with a button to
/// hear it read aloud.
struct ResultView: View {
    let jpeg: Data
    let regions: [TranslatedRegion]
    let target: AppLanguage
    /// How long each step took, shown small under the image. Empty for history items.
    let timings: String
    /// Called when the user says the text was in a different language. Nil hides the picker
    /// (history items keep only the translated image).
    var onChangeSource: ((AppLanguage) -> Void)?

    @State private var speaker = AVSpeechSynthesizer()
    @State private var copied = false

    init(jpeg: Data, regions: [TranslatedRegion], target: AppLanguage, timings: String = "", onChangeSource: ((AppLanguage) -> Void)? = nil) {
        self.jpeg = jpeg
        self.timings = timings
        self.regions = regions
        self.target = target
        self.onChangeSource = onChangeSource
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                languageChip
                if let image = UIImage(data: jpeg) {
                    Image(uiImage: image)
                        .resizable()
                        .scaledToFit()
                        .clipShape(RoundedRectangle(cornerRadius: 12))
                }
                if !timings.isEmpty {
                    Text(timings).font(.caption2).foregroundStyle(.secondary)
                }
                ForEach(Array(regions.enumerated()), id: \.offset) { _, region in
                    VStack(alignment: .leading, spacing: 4) {
                        HStack(alignment: .firstTextBaseline) {
                            Text(region.translated)
                            Spacer()
                            Button {
                                speak(region.translated)
                            } label: {
                                Image(systemName: "speaker.wave.2")
                            }
                            .buttonStyle(.borderless)
                            .accessibilityLabel("Read aloud")
                        }
                        ForEach(region.notes, id: \.self) { note in
                            Text(note)
                                .font(.callout)
                                .foregroundStyle(note.hasPrefix("⚠") ? Color.orange : Color.green)
                        }
                        Text(region.original).font(.footnote).foregroundStyle(.secondary)
                    }
                    .textSelection(.enabled)
                    Divider()
                }
            }
            .padding()
        }
        .navigationTitle("Translation")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
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
        .onDisappear { speaker.stopSpeaking(at: .immediate) }
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
