import Foundation
import Translation

enum LanguageStatus {
    case installed
    case needsDownload
    case unsupported
}

/// Wraps Apple's on-device Translation framework, or the online engine when the user has set
/// one up (see `OnlineTranslator`). With Apple's, nothing is sent to a server.
enum Translator {
    static func status(from source: AppLanguage, to target: AppLanguage) async -> LanguageStatus {
        let status = await LanguageAvailability().status(from: source.localeLanguage, to: target.localeLanguage)
        switch status {
        case .installed: return .installed
        case .supported: return .needsDownload
        case .unsupported: return .unsupported
        @unknown default: return .unsupported
        }
    }

    /// Loads the translation model for a pair by translating a tiny text, so a translation that
    /// follows straight after doesn't wait for it. Fails quietly if the pair isn't downloaded.
    static func warmUp(from source: AppLanguage, to target: AppLanguage) async {
        guard source != target else { return }
        _ = try? await translateWithEngine(["OK"], from: source, to: target, engine: OnlineEngine.active)
    }

    /// Warms up the language the user most likely reads next: the chosen one, or with automatic
    /// detection, the language of the last screenshot.
    static func warmUpLikelyPair() async {
        guard let source = AppSettings.sourceLanguage ?? AppSettings.lastDetectedSource else { return }
        await warmUp(from: source, to: AppSettings.targetLanguage)
    }

    /// Translates the texts and returns them in the same order. Text translated before (menus,
    /// buttons, headings seen on an earlier screen) comes from a cache on this device; the rest
    /// goes to Apple's engine in one batch.
    /// The languages must already be downloaded (see `ContentView`'s Download button),
    /// because the Shortcuts action can't show Apple's download prompt.
    static func translate(_ texts: [String], from source: AppLanguage, to target: AppLanguage) async throws -> [String] {
        let engine = OnlineEngine.active
        let cache = TranslationCache(source: source, target: target, engine: engine)
        var known = cache.load()
        let new = Array(Set(texts.filter { known[$0] == nil }))
        if !new.isEmpty {
            let translated = try await translateWithEngine(new, from: source, to: target, engine: engine)
            for (original, translation) in zip(new, translated) {
                known[original] = translation
            }
            cache.save(known, adding: new)
        }
        return texts.map { known[$0] ?? $0 }
    }

    /// The online engine falls back to Apple's when it fails (no signal, key used up), so a
    /// press never ends in an error the on-device engine could have handled.
    private static func translateWithEngine(_ texts: [String], from source: AppLanguage, to target: AppLanguage, engine: OnlineEngine?) async throws -> [String] {
        guard !texts.isEmpty else { return [] }
        if let engine, let translated = try? await OnlineTranslator.translate(texts, from: source, to: target, engine: engine) {
            return translated
        }

        let session = await SessionCache.shared.session(from: source, to: target)
        let requests = texts.enumerated().map { index, text in
            TranslationSession.Request(sourceText: text, clientIdentifier: String(index))
        }
        let responses: [TranslationSession.Response]
        do {
            responses = try await session.translations(from: requests)
        } catch {
            await SessionCache.shared.discard(from: source, to: target)
            throw error
        }

        var results = texts
        for response in responses {
            if let id = response.clientIdentifier, let index = Int(id), results.indices.contains(index) {
                results[index] = response.targetText
            }
        }
        return results
    }
}

/// Remembers recent translations for one language pair, on this device only. Screens repeat a
/// lot of text (an app's menus and buttons, a page you scroll back to), and Apple's engine takes
/// about a second and a half for a dozen pieces of text, so this is what makes repeat presses fast.
struct TranslationCache {
    static let limit = 3000

    private let url: URL?
    private let orderURL: URL?

    private static var directory: URL? {
        FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask).first?
            .appendingPathComponent("Translations", isDirectory: true)
    }

    /// Forgets every remembered translation.
    static func clearAll() {
        if let directory { try? FileManager.default.removeItem(at: directory) }
    }

    /// Each engine keeps its own memory, so switching engines doesn't show the old engine's wording.
    init(source: AppLanguage, target: AppLanguage, engine: OnlineEngine? = nil) {
        let directory = Self.directory
        if let directory {
            try? FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        }
        let name = (engine.map { "\($0.rawValue)-" } ?? "") + "\(source.rawValue)-\(target.rawValue)"
        url = directory?.appendingPathComponent("\(name).json")
        orderURL = directory?.appendingPathComponent("\(name)-order.json")
    }

    func load() -> [String: String] {
        guard let url, let data = try? Data(contentsOf: url) else { return [:] }
        return (try? JSONDecoder().decode([String: String].self, from: data)) ?? [:]
    }

    /// Saves the translations, forgetting the oldest once there are more than `limit`.
    func save(_ translations: [String: String], adding added: [String]) {
        guard let url, let orderURL else { return }
        var order = ((try? Data(contentsOf: orderURL)).flatMap { try? JSONDecoder().decode([String].self, from: $0) } ?? [])
        order.removeAll { added.contains($0) }
        order.append(contentsOf: added)
        var kept = translations
        if order.count > Self.limit {
            for old in order.prefix(order.count - Self.limit) {
                kept[old] = nil
            }
            order.removeFirst(order.count - Self.limit)
        }
        try? JSONEncoder().encode(kept).write(to: url, options: .atomic)
        try? JSONEncoder().encode(order).write(to: orderURL, options: .atomic)
    }
}

/// Keeps one translation session per language pair, so repeated translations don't pay the
/// start-up cost again (other apps get slower with every use; this keeps the speed steady).
actor SessionCache {
    static let shared = SessionCache()

    private var sessions: [String: TranslationSession] = [:]

    func session(from source: AppLanguage, to target: AppLanguage) -> TranslationSession {
        let key = "\(source.rawValue)>\(target.rawValue)"
        if let session = sessions[key] { return session }
        let session = TranslationSession(installedSource: source.localeLanguage, target: target.localeLanguage)
        sessions[key] = session
        return session
    }

    /// Drops a session that failed, so the next attempt starts fresh.
    func discard(from source: AppLanguage, to target: AppLanguage) {
        sessions["\(source.rawValue)>\(target.rawValue)"] = nil
    }
}
