import Foundation
import Security

/// Optional online translation, with the user's own DeepL or Google Cloud API key. Much faster
/// than Apple's on-device engine for new text (a fraction of a second instead of about two),
/// and usually better with names and slang. Only the text read from the screen is sent, never
/// the image.
enum OnlineEngine: String, CaseIterable, Identifiable {
    case off
    case deepL
    case google

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .off: return "Apple (on this iPhone)"
        case .deepL: return "DeepL (online)"
        case .google: return "Google (online)"
        }
    }

    /// The engine to use for the next translation, or nil for Apple's. Needs Pro and a saved key.
    static var active: OnlineEngine? {
        let engine = OnlineEngine(rawValue: UserDefaults.standard.string(forKey: SettingsKey.onlineEngine) ?? "") ?? .off
        guard engine != .off, engine.hasConsent, Usage.isProCached, APIKeyStore.key(for: engine) != nil else { return nil }
        return engine
    }

    /// The user agreed that text read from screenshots may be sent to this service. Nothing is
    /// sent online without it.
    var hasConsent: Bool {
        get { UserDefaults.standard.bool(forKey: "onlineConsent.\(rawValue)") }
        nonmutating set { UserDefaults.standard.set(newValue, forKey: "onlineConsent.\(rawValue)") }
    }
}

enum OnlineTranslator {
    /// One shared session keeps the connection open between presses, which saves the TLS handshake.
    private static let session: URLSession = {
        let configuration = URLSessionConfiguration.default
        configuration.timeoutIntervalForRequest = 8
        configuration.waitsForConnectivity = false
        return URLSession(configuration: configuration)
    }()

    static func translate(_ texts: [String], from source: AppLanguage, to target: AppLanguage, engine: OnlineEngine, context: String? = nil) async throws -> [String] {
        guard !texts.isEmpty else { return [] }
        guard let key = APIKeyStore.key(for: engine) else { throw OnlineError.noKey }
        switch engine {
        case .deepL: return try await deepL(texts, from: source, to: target, key: key, context: context)
        case .google: return try await google(texts, from: source, to: target, key: key)
        case .off: throw OnlineError.noKey
        }
    }

    /// Opens the connection (DNS, TLS) ahead of the first translation without translating
    /// anything, so it costs nothing against the key's allowance.
    static func preconnect(_ engine: OnlineEngine) async {
        guard let url = URL(string: "https://\(host(for: engine))/") else { return }
        var request = URLRequest(url: url)
        request.httpMethod = "HEAD"
        _ = try? await session.data(for: request)
    }

    private static func host(for engine: OnlineEngine) -> String {
        switch engine {
        case .deepL: return (APIKeyStore.key(for: .deepL) ?? "").hasSuffix(":fx") ? "api-free.deepl.com" : "api.deepl.com"
        case .google, .off: return "translation.googleapis.com"
        }
    }

    /// Checks a key by translating one word, so the settings screen can say whether it works.
    static func test(_ engine: OnlineEngine) async -> String? {
        do {
            _ = try await translate(["こんにちは"], from: .japanese, to: .english, engine: engine)
            return nil
        } catch {
            return error.localizedDescription
        }
    }

    // MARK: - DeepL

    private static func deepL(_ texts: [String], from source: AppLanguage, to target: AppLanguage, key: String, context: String?) async throws -> [String] {
        var request = URLRequest(url: URL(string: "https://\(host(for: .deepL))/v2/translate")!)
        request.httpMethod = "POST"
        request.setValue("DeepL-Auth-Key \(key)", forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        var body: [String: Any] = [
            "text": texts,
            "source_lang": deepLSource(source),
            "target_lang": deepLTarget(target),
        ]
        // The rest of the screen, so a lone button label reads as a button. Not charged.
        if let context, !context.isEmpty { body["context"] = context }
        request.httpBody = try JSONSerialization.data(withJSONObject: body)

        struct Response: Decodable {
            struct Translation: Decodable { let text: String }
            let translations: [Translation]
        }
        let response: Response = try await send(request)
        guard response.translations.count == texts.count else { throw OnlineError.badResponse }
        return response.translations.map(\.text)
    }

    private static func deepLSource(_ language: AppLanguage) -> String {
        switch language {
        case .chineseSimplified, .chineseTraditional: return "ZH"
        case .portuguese: return "PT"
        default: return language.rawValue.uppercased()
        }
    }

    private static func deepLTarget(_ language: AppLanguage) -> String {
        switch language {
        case .english: return "EN-US"
        case .portuguese: return "PT-BR"
        case .chineseSimplified: return "ZH-HANS"
        case .chineseTraditional: return "ZH-HANT"
        default: return language.rawValue.uppercased()
        }
    }

    // MARK: - Google

    private static func google(_ texts: [String], from source: AppLanguage, to target: AppLanguage, key: String) async throws -> [String] {
        var request = URLRequest(url: URL(string: "https://\(host(for: .google))/language/translate/v2")!)
        request.httpMethod = "POST"
        request.setValue(key, forHTTPHeaderField: "X-Goog-Api-Key")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = try JSONSerialization.data(withJSONObject: [
            "q": texts,
            "source": googleCode(source),
            "target": googleCode(target),
            "format": "text",
        ])

        struct Response: Decodable {
            struct Body: Decodable {
                struct Translation: Decodable { let translatedText: String }
                let translations: [Translation]
            }
            let data: Body
        }
        let response: Response = try await send(request)
        guard response.data.translations.count == texts.count else { throw OnlineError.badResponse }
        return response.data.translations.map(\.translatedText)
    }

    private static func googleCode(_ language: AppLanguage) -> String {
        switch language {
        case .chineseSimplified: return "zh-CN"
        case .chineseTraditional: return "zh-TW"
        case .portuguese: return "pt"
        default: return language.rawValue
        }
    }

    // MARK: - Helpers

    private static func send<Response: Decodable>(_ request: URLRequest) async throws -> Response {
        let (data, response) = try await session.data(for: request)
        let code = (response as? HTTPURLResponse)?.statusCode ?? 0
        switch code {
        case 200: break
        case 401, 403: throw OnlineError.rejectedKey
        case 429, 456: throw OnlineError.quotaReached
        default: throw OnlineError.server(code)
        }
        do {
            return try JSONDecoder().decode(Response.self, from: data)
        } catch {
            throw OnlineError.badResponse
        }
    }
}

enum OnlineError: LocalizedError {
    case noKey, rejectedKey, quotaReached, badResponse, server(Int)

    var errorDescription: String? {
        switch self {
        case .noKey: return "No API key saved."
        case .rejectedKey: return "The API key was rejected. Check that it was copied in full."
        case .quotaReached: return "The key's monthly allowance is used up."
        case .badResponse: return "The translation service sent an answer the app couldn't read."
        case .server(let code): return "The translation service returned error \(code)."
        }
    }
}

/// Keeps API keys in the Keychain. They stay readable while the iPhone is locked (after the
/// first unlock since a restart), so the Shortcuts action can use them.
enum APIKeyStore {
    private static let service = "com.aamack6.ScreenTranslate.apikey"

    static func key(for engine: OnlineEngine) -> String? {
        let query: [CFString: Any] = [
            kSecClass: kSecClassGenericPassword,
            kSecAttrService: service,
            kSecAttrAccount: engine.rawValue,
            kSecReturnData: true,
        ]
        var result: AnyObject?
        guard SecItemCopyMatching(query as CFDictionary, &result) == errSecSuccess,
              let data = result as? Data, let key = String(data: data, encoding: .utf8), !key.isEmpty else { return nil }
        return key
    }

    /// Saves the key, or removes it when `key` is empty.
    static func setKey(_ key: String, for engine: OnlineEngine) {
        let match: [CFString: Any] = [
            kSecClass: kSecClassGenericPassword,
            kSecAttrService: service,
            kSecAttrAccount: engine.rawValue,
        ]
        SecItemDelete(match as CFDictionary)
        let trimmed = key.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        var item = match
        item[kSecValueData] = Data(trimmed.utf8)
        item[kSecAttrAccessible] = kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly
        SecItemAdd(item as CFDictionary, nil)
    }
}
