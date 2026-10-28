import Foundation
import Translation

enum LanguageStatus {
    case installed
    case needsDownload
    case unsupported
}

/// Wraps Apple's on-device Translation framework. Nothing is sent to a server.
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
        _ = try? await translate(["OK"], from: source, to: target)
    }

    /// Warms up the language the user most likely reads next: the chosen one, or with automatic
    /// detection, the language of the last screenshot.
    static func warmUpLikelyPair() async {
        guard let source = AppSettings.sourceLanguage ?? AppSettings.lastDetectedSource else { return }
        await warmUp(from: source, to: AppSettings.targetLanguage)
    }

    /// Translates the texts in one batch and returns them in the same order.
    /// The languages must already be downloaded (see `ContentView`'s Download button),
    /// because the Shortcuts action can't show Apple's download prompt.
    static func translate(_ texts: [String], from source: AppLanguage, to target: AppLanguage) async throws -> [String] {
        guard !texts.isEmpty else { return [] }

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
