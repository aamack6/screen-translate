import Foundation

struct HistoryItem: Codable, Identifiable {
    let id: UUID
    let date: Date
    let target: AppLanguage
    let regions: [TranslatedRegion]

    var fileName: String { "\(id.uuidString).png" }
}

/// Keeps recent translations in the app's own storage on this device. Nothing leaves the phone.
/// Off by default; the user turns it on in the app.
struct HistoryStore {
    static let limit = 30

    private let directory: URL
    private var indexURL: URL { directory.appendingPathComponent("history.json") }

    init(fileManager: FileManager = .default) {
        let base = fileManager.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
        directory = base.appendingPathComponent("History", isDirectory: true)
        try? fileManager.createDirectory(at: directory, withIntermediateDirectories: true)
    }

    func load() -> [HistoryItem] {
        guard let data = try? Data(contentsOf: indexURL) else { return [] }
        return (try? JSONDecoder().decode([HistoryItem].self, from: data)) ?? []
    }

    func add(_ result: RenderedTranslation) throws {
        let item = HistoryItem(id: UUID(), date: Date(), target: result.target, regions: result.regions)
        try result.png.write(to: directory.appendingPathComponent(item.fileName), options: .completeFileProtectionUntilFirstUserAuthentication)

        var items = [item] + load()
        for old in items.dropFirst(Self.limit) {
            try? FileManager.default.removeItem(at: directory.appendingPathComponent(old.fileName))
        }
        items = Array(items.prefix(Self.limit))
        try save(items)
    }

    func imageData(for item: HistoryItem) -> Data? {
        try? Data(contentsOf: directory.appendingPathComponent(item.fileName))
    }

    func clear() throws {
        for item in load() {
            try? FileManager.default.removeItem(at: directory.appendingPathComponent(item.fileName))
        }
        try save([])
    }

    private func save(_ items: [HistoryItem]) throws {
        try JSONEncoder().encode(items).write(to: indexURL, options: [.atomic, .completeFileProtectionUntilFirstUserAuthentication])
    }
}
