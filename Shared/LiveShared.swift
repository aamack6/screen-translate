import CoreGraphics
import Foundation
import Network

/// What the app and the screen broadcast extension share during live translation. They run as
/// separate processes and talk over a TCP connection on the phone's loopback interface
/// (127.0.0.1), which never leaves the device. That works with any signing team; an App Group
/// container would need a paid developer account.
enum LiveShared {
    static let broadcastExtensionID = "com.aamack6.ScreenTranslate.Broadcast"
    static let port: UInt16 = 52741
}

/// One message on the live connection. The extension sends `state` and `frame`; the app sends
/// `config`.
struct LiveMessage: Codable {
    var state: LiveState?
    var frame: LiveFrame?
    var config: LiveConfig?
}

/// Sends and receives `LiveMessage`s on a connection, each as a 4-byte length and then JSON.
final class LiveLink {
    let connection: NWConnection
    var onMessage: ((LiveMessage) -> Void)?
    var onClose: (() -> Void)?
    private let queue: DispatchQueue

    init(_ connection: NWConnection, queue: DispatchQueue) {
        self.connection = connection
        self.queue = queue
    }

    /// Connects to the app. Used by the extension.
    static func toApp(queue: DispatchQueue) -> LiveLink {
        let parameters = NWParameters.tcp
        parameters.requiredInterfaceType = .loopback
        let connection = NWConnection(host: "127.0.0.1", port: NWEndpoint.Port(rawValue: LiveShared.port)!, using: parameters)
        return LiveLink(connection, queue: queue)
    }

    func start() {
        connection.stateUpdateHandler = { [weak self] state in
            switch state {
            case .failed, .cancelled: self?.close()
            default: break
            }
        }
        connection.start(queue: queue)
        receive()
    }

    func send(_ message: LiveMessage) {
        guard let body = try? JSONEncoder().encode(message) else { return }
        var length = UInt32(body.count).bigEndian
        var data = Data(bytes: &length, count: 4)
        data.append(body)
        connection.send(content: data, completion: .contentProcessed { _ in })
    }

    func cancel() {
        connection.cancel()
    }

    private var closed = false
    private func close() {
        guard !closed else { return }
        closed = true
        onClose?()
    }

    private func receive() {
        connection.receive(minimumIncompleteLength: 4, maximumLength: 4) { [weak self] header, _, isComplete, error in
            guard let self else { return }
            guard let header, header.count == 4, error == nil else {
                if isComplete || error != nil { self.connection.cancel() }
                return
            }
            let length = Int(header.reduce(UInt32(0)) { $0 << 8 | UInt32($1) })
            guard length > 0, length < 4_000_000 else { self.connection.cancel(); return }
            self.connection.receive(minimumIncompleteLength: length, maximumLength: length) { body, _, _, error in
                guard let body, body.count == length, error == nil else { self.connection.cancel(); return }
                if let message = try? JSONDecoder().decode(LiveMessage.self, from: body) {
                    self.onMessage?(message)
                }
                self.receive()
            }
        }
    }
}

/// The languages to read, sent by the app when the extension connects and when they change.
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

/// The foreign text currently on screen, sent by the extension when it changes.
struct LiveFrame: Codable {
    var date: Date
    var blocks: [LiveBlock]
}

struct LiveState: Codable {
    var isBroadcasting: Bool
}
