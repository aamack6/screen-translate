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

    /// Translates the texts in one batch and returns them in the same order.
    /// The languages must already be downloaded (see `ContentView`'s Download button),
    /// because the Shortcuts action can't show Apple's download prompt.
    static func translate(_ texts: [String], from source: AppLanguage, to target: AppLanguage) async throws -> [String] {
        guard !texts.isEmpty else { return [] }

        let session = TranslationSession(installedSource: source.localeLanguage, target: target.localeLanguage)
        let requests = texts.enumerated().map { index, text in
            TranslationSession.Request(sourceText: text, clientIdentifier: String(index))
        }
        let responses = try await session.translations(from: requests)

        var results = texts
        for response in responses {
            if let id = response.clientIdentifier, let index = Int(id), results.indices.contains(index) {
                results[index] = response.targetText
            }
        }
        return results
    }
}
