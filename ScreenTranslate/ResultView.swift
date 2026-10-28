import SwiftUI

/// Shows a translated screenshot with its translations as selectable text.
struct ResultView: View {
    let png: Data
    let regions: [TranslatedRegion]

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
                        Text(region.translated)
                        Text(region.original).font(.footnote).foregroundStyle(.secondary)
                    }
                    .textSelection(.enabled)
                    Divider()
                }
            }
            .padding()
        }
        .navigationTitle("Translated screenshot")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            if let image = UIImage(data: png) {
                ShareLink(
                    item: Image(uiImage: image),
                    preview: SharePreview("Translated screenshot", image: Image(uiImage: image))
                )
            }
        }
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
                        ResultView(png: png, regions: item.regions)
                    }
                } label: {
                    VStack(alignment: .leading) {
                        Text(item.regions.first?.translated ?? "Translation").lineLimit(2)
                        Text("\(item.source.displayName) · \(item.date.formatted(date: .abbreviated, time: .shortened))")
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
