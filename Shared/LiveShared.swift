import CoreGraphics
import Foundation

/// What the app and the screen broadcast extension share during live translation. They run as
/// separate processes, so they talk through files in the App Group container plus a system-wide
/// (Darwin) notification that says "a file changed".
enum LiveShared {
    static let appGroup = "group.com.aamack6.ScreenTranslate"
    static let broadcastExtensionID = "com.aamack6.ScreenTranslate.Broadcast"

    static let frameNotification = "com.aamack6.ScreenTranslate.live.frame"
    static let stateNotification = "com.aamack6.ScreenTranslate.live.state"

    static var frameURL: URL? { container?.appendingPathComponent("live-frame.json") }
    static var configURL: URL? { container?.appendingPathComponent("live-config.json") }
    static var stateURL: URL? { container?.appendingPathComponent("live-state.json") }

    private static var container: URL? {
        FileManager.default.containerURL(forSecurityApplicationGroupIdentifier: appGroup)
    }

    static func write<Value: Encodable>(_ value: Value, to url: URL?) {
        guard let url, let data = try? JSONEncoder().encode(value) else { return }
        try? data.write(to: url, options: .atomic)
    }

    static func read<Value: Decodable>(_ type: Value.Type, from url: URL?) -> Value? {
        guard let url, let data = try? Data(contentsOf: url) else { return nil }
        return try? JSONDecoder().decode(type, from: data)
    }

    static func post(_ name: String) {
        CFNotificationCenterPostNotification(
            CFNotificationCenterGetDarwinNotifyCenter(),
            CFNotificationName(name as CFString),
            nil, nil, true
        )
    }
}

/// The languages to read, written by the app and read by the extension before each pass.
struct LiveConfig: Codable {
    var source: AppLanguage?
    var target: AppLanguage
    /// Seconds between reads of the screen.
    var interval: Double = 1

    static var current: LiveConfig {
        LiveConfig(source: AppSettings.sourceLanguage, target: AppSettings.targetLanguage)
    }
}

/// One paragraph of foreign text on screen.
struct LiveBlock: Codable, Hashable {
    var text: String
    var language: AppLanguage
    /// Position on screen, 0...1 with a top-left origin.
    var rect: CGRect
}

/// The foreign text currently on screen, written by the extension when it changes.
struct LiveFrame: Codable {
    var date: Date
    var blocks: [LiveBlock]
}

struct LiveState: Codable {
    var isBroadcasting: Bool
}
