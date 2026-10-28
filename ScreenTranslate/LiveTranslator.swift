import AVKit
import CoreMedia
import Network
import UIKit

/// Live mode, app side. The broadcast extension sends the foreign text on screen; this translates
/// it and draws it into a Picture-in-Picture window that floats over every app. iOS doesn't let
/// apps draw over other apps, so a PiP "video" of the translations is the closest it allows.
@MainActor
final class LiveTranslator: NSObject, ObservableObject {
    static let shared = LiveTranslator()

    @Published private(set) var isBroadcasting = false
    @Published private(set) var isFloating = false
    @Published private(set) var canFloat = false
    @Published private(set) var isPaused = false

    /// Shown in the app and, through PiP, over other apps.
    let displayLayer = AVSampleBufferDisplayLayer()

    private var pip: AVPictureInPictureController?
    private var possibleObservation: NSKeyValueObservation?
    /// Original text → translation, so text that stays on screen isn't translated again.
    private var translations: [String: String] = [:]
    private var translationsTarget: AppLanguage?
    private var lastFrameDate: Date?
    private var lastFrameArrival: Date?
    /// The screen as last seen, shown again on resume (the extension only sends changes).
    private var latestFrame: LiveFrame?
    private var work: Task<Void, Never>?
    private var listener: NWListener?
    /// The connection from the broadcast extension, while it runs.
    private var link: LiveLink?

    private override init() {
        super.init()
        listen()
    }

    /// Tells the extension which languages to read. Called whenever they change in the app.
    func writeConfig() {
        link?.send(LiveMessage(config: LiveConfig.current))
    }

    // MARK: - Connection to the extension

    /// Waits for the broadcast extension on the loopback interface. iOS may stop the listener
    /// while the app is in the background without the floating window; `prepare()` restarts it.
    private func listen() {
        guard listener == nil else { return }
        let parameters = NWParameters.tcp
        parameters.requiredInterfaceType = .loopback
        parameters.allowLocalEndpointReuse = true
        guard let port = NWEndpoint.Port(rawValue: LiveShared.port),
              let listener = try? NWListener(using: parameters, on: port) else { return }
        listener.newConnectionHandler = { [weak self] connection in
            MainActor.assumeIsolated { self?.accept(connection) }
        }
        listener.stateUpdateHandler = { [weak self] state in
            switch state {
            case .failed, .cancelled:
                MainActor.assumeIsolated {
                    self?.listener?.cancel()
                    self?.listener = nil
                }
            default: break
            }
        }
        self.listener = listener
        listener.start(queue: .main)
    }

    private func accept(_ connection: NWConnection) {
        link?.cancel()
        let link = LiveLink(connection, queue: .main)
        link.onMessage = { [weak self] message in
            MainActor.assumeIsolated { self?.received(message) }
        }
        link.onClose = { [weak self, weak link] in
            MainActor.assumeIsolated {
                guard let self, self.link === link else { return }
                self.link = nil
                self.isBroadcasting = false
                self.lastFrameArrival = nil
                self.showStatus()
            }
        }
        self.link = link
        link.start()
        link.send(LiveMessage(config: LiveConfig.current))
    }

    private func received(_ message: LiveMessage) {
        if let state = message.state {
            isBroadcasting = state.isBroadcasting
            lastFrameArrival = nil
            showStatus()
        }
        if let frame = message.frame {
            frameArrived(frame)
        }
    }

    /// Sets up the floating window. Call when the live screen appears; PiP can only start from a
    /// layer that's on screen.
    func prepare() {
        listen()
        writeConfig()
        guard pip == nil, AVPictureInPictureController.isPictureInPictureSupported() else { return }

        // PiP needs a playback audio session, though nothing is played. Mixing keeps the user's
        // music and videos playing.
        try? AVAudioSession.sharedInstance().setCategory(.playback, mode: .moviePlayback, options: [.mixWithOthers])
        try? AVAudioSession.sharedInstance().setActive(true)

        displayLayer.videoGravity = .resizeAspect
        let source = AVPictureInPictureController.ContentSource(sampleBufferDisplayLayer: displayLayer, playbackDelegate: self)
        let controller = AVPictureInPictureController(contentSource: source)
        controller.delegate = self
        // Leaving the app with the live screen open opens the floating window by itself.
        controller.canStartPictureInPictureAutomaticallyFromInline = true
        possibleObservation = controller.observe(\.isPictureInPicturePossible, options: [.initial, .new]) { [weak self] controller, _ in
            let possible = controller.isPictureInPicturePossible
            Task { @MainActor in self?.canFloat = possible }
        }
        pip = controller
        showStatus()
    }

    /// Pauses or resumes translating, from the floating window's play button or the Shortcuts
    /// action (Action Button, Control Center).
    func togglePaused() {
        isPaused.toggle()
        showStatus()
        pip?.invalidatePlaybackState()
        if !isPaused, let latestFrame {
            lastFrameDate = nil
            frameArrived(latestFrame)
        }
    }

    func toggleFloating() {
        guard let pip else { return }
        if pip.isPictureInPictureActive {
            pip.stopPictureInPicture()
        } else {
            pip.startPictureInPicture()
        }
    }

    // MARK: - Updates

    private func frameArrived(_ frame: LiveFrame) {
        latestFrame = frame
        guard !isPaused, frame.date != lastFrameDate else { return }
        lastFrameDate = frame.date
        isBroadcasting = true

        if !Usage.isProCached {
            // Count time between screen changes, capped so a phone left on one screen isn't charged.
            let now = Date()
            if let last = lastFrameArrival {
                Usage.recordLiveSeconds(min(now.timeIntervalSince(last), 10))
            }
            lastFrameArrival = now
            if Usage.liveSecondsRemainingToday <= 0 {
                show(["Today's \(Usage.freeLiveMinutesPerDay) free minutes of live translation are used up."],
                     footer: "Unlock Pro in ScreenTranslate for unlimited live mode.")
                return
            }
        }

        work?.cancel()
        work = Task { await translateAndShow(frame) }
    }

    private func translateAndShow(_ frame: LiveFrame) async {
        let target = AppSettings.targetLanguage
        if translationsTarget != target || translations.count > 1000 {
            translations = [:]
            translationsTarget = target
        }

        var missingPairs: [String] = []
        let untranslated = frame.blocks.filter { translations[$0.text] == nil }
        for (language, blocks) in Dictionary(grouping: untranslated, by: \.language) {
            switch await Translator.status(from: language, to: target) {
            case .installed:
                let texts = blocks.map(\.text)
                guard let translated = try? await Translator.translate(texts, from: language, to: target) else { continue }
                for (original, translation) in zip(texts, translated) {
                    translations[original] = translation
                }
            case .needsDownload:
                missingPairs.append("\(language.displayName) → \(target.displayName)")
            case .unsupported:
                continue
            }
        }
        guard !Task.isCancelled else { return }

        // Top to bottom, the way the screen reads.
        let ordered = frame.blocks.sorted {
            abs($0.rect.minY - $1.rect.minY) < 0.01 ? $0.rect.minX < $1.rect.minX : $0.rect.minY < $1.rect.minY
        }
        let lines = ordered.compactMap { translations[$0.text] }
        let footer = missingPairs.isEmpty ? nil : "Download \(missingPairs.joined(separator: ", ")) in ScreenTranslate."
        if LiveLayout.current == .screen, let aspect = frame.aspect {
            let placed = ordered.compactMap { block in translations[block.text].map { (rect: block.rect, text: $0) } }
            enqueue(LivePanelRenderer.sampleBuffer(screen: placed, thumbnail: frame.thumbnail, aspect: aspect, footer: footer))
        } else {
            show(lines.isEmpty ? ["No foreign text on screen."] : lines, footer: footer)
        }
    }

    private func showStatus() {
        if isPaused {
            show(["Paused"], footer: "Press play to keep translating.")
        } else if isBroadcasting {
            show(["Waiting for foreign text…"], footer: nil)
        } else {
            show(["Live translation is off."], footer: "Open ScreenTranslate and start screen sharing.")
        }
    }

    private func show(_ lines: [String], footer: String?) {
        enqueue(LivePanelRenderer.sampleBuffer(lines: lines, footer: footer))
    }

    private func enqueue(_ buffer: CMSampleBuffer?) {
        guard let buffer else { return }
        let renderer = displayLayer.sampleBufferRenderer
        if renderer.status == .failed {
            renderer.flush()
        }
        renderer.enqueue(buffer)
    }
}

// MARK: - Picture in Picture

extension LiveTranslator: AVPictureInPictureControllerDelegate {
    nonisolated func pictureInPictureControllerDidStartPictureInPicture(_ pictureInPictureController: AVPictureInPictureController) {
        Task { @MainActor in self.isFloating = true }
    }

    nonisolated func pictureInPictureControllerDidStopPictureInPicture(_ pictureInPictureController: AVPictureInPictureController) {
        Task { @MainActor in self.isFloating = false }
    }
}

extension LiveTranslator: AVPictureInPictureSampleBufferPlaybackDelegate {
    /// The play/pause button in the floating window pauses translating.
    nonisolated func pictureInPictureController(_ pictureInPictureController: AVPictureInPictureController, setPlaying playing: Bool) {
        Task { @MainActor in
            if self.isPaused == playing { self.togglePaused() }
        }
    }

    /// A live stream: no timeline, no skipping.
    nonisolated func pictureInPictureControllerTimeRangeForPlayback(_ pictureInPictureController: AVPictureInPictureController) -> CMTimeRange {
        CMTimeRange(start: .negativeInfinity, duration: .positiveInfinity)
    }

    nonisolated func pictureInPictureControllerIsPlaybackPaused(_ pictureInPictureController: AVPictureInPictureController) -> Bool {
        MainActor.assumeIsolated { isPaused }
    }

    nonisolated func pictureInPictureController(_ pictureInPictureController: AVPictureInPictureController, didTransitionToRenderSize newRenderSize: CMVideoDimensions) {}

    nonisolated func pictureInPictureController(_ pictureInPictureController: AVPictureInPictureController, skipByInterval skipInterval: CMTime, completion completionHandler: @escaping () -> Void) {
        completionHandler()
    }
}

// MARK: - Drawing

/// What the floating window shows.
enum LiveLayout: String, CaseIterable, Identifiable {
    /// A small faded copy of the screen with each translation where its text is.
    case screen
    /// The translations as a list, in a short strip.
    case list

    var id: String { rawValue }

    var name: String {
        switch self {
        case .screen: return "Screen layout"
        case .list: return "List"
        }
    }

    static let settingsKey = "liveLayout"

    static var current: LiveLayout {
        LiveLayout(rawValue: UserDefaults.standard.string(forKey: settingsKey) ?? "") ?? .screen
    }
}

/// Draws the translations as a "video frame" for the floating window.
enum LivePanelRenderer {
    /// A wide 9:4 strip, so the window covers little of the screen but fits a few lines. Users can
    /// pinch it larger, or swipe it to the edge of the screen to tuck it away.
    /// It's drawn at a low resolution on purpose: the window scales the frame to fit, so fewer
    /// pixels mean larger text.
    static let size = CGSize(width: 450, height: 200)

    static func sampleBuffer(lines: [String], footer: String?) -> CMSampleBuffer? {
        guard let image = render(lines: lines, footer: footer).cgImage,
              let pixelBuffer = pixelBuffer(from: image) else { return nil }
        return sampleBuffer(from: pixelBuffer)
    }

    private static func render(lines: [String], footer: String?) -> UIImage {
        let format = UIGraphicsImageRendererFormat()
        format.scale = 1
        format.opaque = true
        return UIGraphicsImageRenderer(size: size, format: format).image { context in
            UIColor(white: 0.08, alpha: 1).setFill()
            context.fill(CGRect(origin: .zero, size: size))

            let inset: CGFloat = 10
            let width = size.width - inset * 2
            var bottom = size.height - inset
            if let footer {
                let footerText = NSAttributedString(string: footer, attributes: [
                    .font: UIFont.systemFont(ofSize: 13, weight: .medium),
                    .foregroundColor: UIColor.systemOrange,
                ])
                let height = footerText.boundingRect(with: CGSize(width: width, height: .greatestFiniteMagnitude), options: .usesLineFragmentOrigin, context: nil).height
                bottom -= ceil(height)
                footerText.draw(with: CGRect(x: inset, y: bottom, width: width, height: height), options: .usesLineFragmentOrigin, context: nil)
                bottom -= 5
            }

            // Shrink the text until everything fits, down to a size that's still readable;
            // past that, the lowest lines are cut.
            let available = bottom - inset
            var fontSize: CGFloat = 20
            var text = attributed(lines, fontSize: fontSize)
            while fontSize > 15, height(of: text, width: width) > available {
                fontSize -= 2
                text = attributed(lines, fontSize: fontSize)
            }
            text.draw(with: CGRect(x: inset, y: inset, width: width, height: available), options: [.usesLineFragmentOrigin, .truncatesLastVisibleLine], context: nil)
        }
    }

    /// Draws a faded copy of the screen with each translation on a panel where its text is.
    /// Translations are longer than the Japanese they replace, so a panel may grow downward,
    /// and its text shrinks until it fits.
    static func sampleBuffer(screen blocks: [(rect: CGRect, text: String)], thumbnail: Data?, aspect: Double, footer: String?) -> CMSampleBuffer? {
        // Few pixels on purpose, as with the list: the window scales the frame down, and text has
        // to stay readable at half the screen's width.
        let width: CGFloat = 300
        let canvas = CGSize(width: width, height: (width * CGFloat(min(max(aspect, 0.4), 2.5)) / 2).rounded() * 2)
        let format = UIGraphicsImageRendererFormat()
        format.scale = 1
        format.opaque = true
        let image = UIGraphicsImageRenderer(size: canvas, format: format).image { context in
            UIColor(white: 0.08, alpha: 1).setFill()
            context.fill(CGRect(origin: .zero, size: canvas))
            if let thumbnail, let screen = UIImage(data: thumbnail) {
                screen.draw(in: CGRect(origin: .zero, size: canvas), blendMode: .normal, alpha: 0.4)
            }

            for block in blocks {
                var panel = CGRect(
                    x: block.rect.minX * canvas.width,
                    y: block.rect.minY * canvas.height,
                    width: block.rect.width * canvas.width,
                    height: block.rect.height * canvas.height
                ).insetBy(dx: -2, dy: -1)
                panel.size.width = min(max(panel.width, 80), canvas.width - max(panel.minX, 0))
                let textWidth = panel.width - 4

                // Readability comes first: text never goes below 12 px, and the panel grows
                // downward (over the faded screen) to fit it.
                var fontSize = min(max(panel.height * 0.9, 14), 18)
                var text = panelText(block.text, fontSize: fontSize)
                while fontSize > 12, height(of: text, width: textWidth) > max(panel.height, fontSize * 3.6) {
                    fontSize -= 1
                    text = panelText(block.text, fontSize: fontSize)
                }
                panel.size.height = max(panel.height, min(height(of: text, width: textWidth) + 2, canvas.height - panel.minY))

                UIColor(white: 1, alpha: 0.93).setFill()
                UIBezierPath(roundedRect: panel, cornerRadius: 3).fill()
                text.draw(with: panel.insetBy(dx: 2, dy: 1), options: [.usesLineFragmentOrigin, .truncatesLastVisibleLine], context: nil)
            }

            if let footer {
                let footerText = NSAttributedString(string: footer, attributes: [
                    .font: UIFont.systemFont(ofSize: 12, weight: .medium),
                    .foregroundColor: UIColor.systemOrange,
                ])
                let band = CGRect(x: 0, y: canvas.height - 34, width: canvas.width, height: 34)
                UIColor(white: 0.08, alpha: 0.9).setFill()
                context.fill(band)
                footerText.draw(with: band.insetBy(dx: 8, dy: 4), options: [.usesLineFragmentOrigin, .truncatesLastVisibleLine], context: nil)
            }
        }
        guard let cgImage = image.cgImage, let pixelBuffer = pixelBuffer(from: cgImage) else { return nil }
        return sampleBuffer(from: pixelBuffer)
    }

    private static func panelText(_ text: String, fontSize: CGFloat) -> NSAttributedString {
        NSAttributedString(string: text, attributes: [
            .font: UIFont.systemFont(ofSize: fontSize, weight: .semibold),
            .foregroundColor: UIColor.black,
        ])
    }

    private static func attributed(_ lines: [String], fontSize: CGFloat) -> NSAttributedString {
        let paragraph = NSMutableParagraphStyle()
        paragraph.paragraphSpacing = fontSize * 0.6
        return NSAttributedString(string: lines.joined(separator: "\n"), attributes: [
            .font: UIFont.systemFont(ofSize: fontSize, weight: .semibold),
            .foregroundColor: UIColor.white,
            .paragraphStyle: paragraph,
        ])
    }

    private static func height(of text: NSAttributedString, width: CGFloat) -> CGFloat {
        text.boundingRect(with: CGSize(width: width, height: .greatestFiniteMagnitude), options: .usesLineFragmentOrigin, context: nil).height
    }

    private static func pixelBuffer(from image: CGImage) -> CVPixelBuffer? {
        let attributes: [CFString: Any] = [
            kCVPixelBufferCGImageCompatibilityKey: true,
            kCVPixelBufferCGBitmapContextCompatibilityKey: true,
            kCVPixelBufferIOSurfacePropertiesKey: [:] as CFDictionary,
        ]
        var buffer: CVPixelBuffer?
        guard CVPixelBufferCreate(kCFAllocatorDefault, image.width, image.height, kCVPixelFormatType_32BGRA, attributes as CFDictionary, &buffer) == kCVReturnSuccess,
              let buffer else { return nil }

        CVPixelBufferLockBaseAddress(buffer, [])
        defer { CVPixelBufferUnlockBaseAddress(buffer, []) }
        guard let context = CGContext(
            data: CVPixelBufferGetBaseAddress(buffer),
            width: image.width,
            height: image.height,
            bitsPerComponent: 8,
            bytesPerRow: CVPixelBufferGetBytesPerRow(buffer),
            space: CGColorSpaceCreateDeviceRGB(),
            bitmapInfo: CGImageAlphaInfo.premultipliedFirst.rawValue | CGBitmapInfo.byteOrder32Little.rawValue
        ) else { return nil }
        context.draw(image, in: CGRect(x: 0, y: 0, width: image.width, height: image.height))
        return buffer
    }

    private static func sampleBuffer(from pixelBuffer: CVPixelBuffer) -> CMSampleBuffer? {
        var format: CMVideoFormatDescription?
        CMVideoFormatDescriptionCreateForImageBuffer(allocator: kCFAllocatorDefault, imageBuffer: pixelBuffer, formatDescriptionOut: &format)
        guard let format else { return nil }

        var timing = CMSampleTimingInfo(
            duration: .invalid,
            presentationTimeStamp: CMClockGetTime(CMClockGetHostTimeClock()),
            decodeTimeStamp: .invalid
        )
        var sampleBuffer: CMSampleBuffer?
        CMSampleBufferCreateReadyWithImageBuffer(
            allocator: kCFAllocatorDefault,
            imageBuffer: pixelBuffer,
            formatDescription: format,
            sampleTiming: &timing,
            sampleBufferOut: &sampleBuffer
        )
        guard let sampleBuffer else { return nil }

        // Show each frame as soon as it arrives instead of waiting for its timestamp.
        if let attachments = CMSampleBufferGetSampleAttachmentsArray(sampleBuffer, createIfNecessary: true),
           CFArrayGetCount(attachments) > 0 {
            let dictionary = unsafeBitCast(CFArrayGetValueAtIndex(attachments, 0), to: CFMutableDictionary.self)
            CFDictionarySetValue(
                dictionary,
                Unmanaged.passUnretained(kCMSampleAttachmentKey_DisplayImmediately).toOpaque(),
                Unmanaged.passUnretained(kCFBooleanTrue).toOpaque()
            )
        }
        return sampleBuffer
    }
}
