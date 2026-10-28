import AVFoundation
import SwiftUI

/// Shows a translated image with its translations as selectable text, each with a button to
/// hear it read aloud.
struct ResultView: View {
    let png: Data
    let regions: [TranslatedRegion]
    let target: AppLanguage

    @State private var speaker = AVSpeechSynthesizer()
    @State private var copied = false

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                if let image = UIImage(data: png) {
                    Image(uiImage: image)
                        .resizable()
                        .scaledToFit()
                        .clipShape(RoundedRectangle(cornerRadius: 12))
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
            if let image = UIImage(data: png) {
                ShareLink(
                    item: Image(uiImage: image),
                    preview: SharePreview("Translated image", image: Image(uiImage: image))
                )
            }
        }
        .onDisappear { speaker.stopSpeaking(at: .immediate) }
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
                    if let png = store.imageData(for: item) {
                        ResultView(png: png, regions: item.regions, target: item.target)
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
            if !items.isEmpty {
                Button("Clear", role: .destructive) {
                    try? store.clear()
                    items = []
                }
            }
        }
        .onAppear { items = store.load() }
    }
}
