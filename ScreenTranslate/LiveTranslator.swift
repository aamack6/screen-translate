import AVKit
import CoreMedia
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
    private var work: Task<Void, Never>?

    private override init() {
        super.init()
        let center = CFNotificationCenterGetDarwinNotifyCenter()
        let observer = Unmanaged.passUnretained(self).toOpaque()
        for name in [LiveShared.frameNotification, LiveShared.stateNotification] {
            CFNotificationCenterAddObserver(center, observer, liveNotificationCallback, name as CFString, nil, .deliverImmediately)
        }
        isBroadcasting = LiveShared.read(LiveState.self, from: LiveShared.stateURL)?.isBroadcasting ?? false
    }

    /// Tells the extension which languages to read. Called whenever they change in the app.
    func writeConfig() {
        LiveShared.write(LiveConfig.current, to: LiveShared.configURL)
    }

    /// Sets up the floating window. Call when the live screen appears; PiP can only start from a
    /// layer that's on screen.
    func prepare() {
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

    func toggleFloating() {
        guard let pip else { return }
        if pip.isPictureInPictureActive {
            pip.stopPictureInPicture()
        } else {
            pip.startPictureInPicture()
        }
    }

    // MARK: - Updates

    fileprivate func notificationArrived(_ name: String) {
        if name == LiveShared.stateNotification {
            isBroadcasting = LiveShared.read(LiveState.self, from: LiveShared.stateURL)?.isBroadcasting ?? false
            lastFrameArrival = nil
            showStatus()
        } else {
            frameArrived()
        }
    }

    private func frameArrived() {
        guard !isPaused, let frame = LiveShared.read(LiveFrame.self, from: LiveShared.frameURL), frame.date != lastFrameDate else { return }
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
        show(lines.isEmpty ? ["No foreign text on screen."] : lines, footer: footer)
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
        guard let buffer = LivePanelRenderer.sampleBuffer(lines: lines, footer: footer) else { return }
        let renderer = displayLayer.sampleBufferRenderer
        if renderer.status == .failed {
            renderer.flush()
        }
        renderer.enqueue(buffer)
    }
}

/// Darwin notifications carry no data and need a plain C function, so this hops back to the
/// shared translator by its pointer.
private let liveNotificationCallback: CFNotificationCallback = { _, observer, name, _, _ in
    guard let observer, let name = name.map({ $0.rawValue as String }) else { return }
    let translator = Unmanaged<LiveTranslator>.fromOpaque(observer).takeUnretainedValue()
    Task { @MainActor in translator.notificationArrived(name) }
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
            self.isPaused = !playing
            self.showStatus()
            pictureInPictureController.invalidatePlaybackState()
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

/// Draws the translations as a "video frame" for the floating window.
enum LivePanelRenderer {
    /// Portrait 3:4, so the window sits comfortably beside content. Users can pinch it larger.
    static let size = CGSize(width: 480, height: 640)

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

            let inset: CGFloat = 20
            let width = size.width - inset * 2
            var bottom = size.height - inset
            if let footer {
                let footerText = NSAttributedString(string: footer, attributes: [
                    .font: UIFont.systemFont(ofSize: 18, weight: .medium),
                    .foregroundColor: UIColor.systemOrange,
                ])
                let height = footerText.boundingRect(with: CGSize(width: width, height: .greatestFiniteMagnitude), options: .usesLineFragmentOrigin, context: nil).height
                bottom -= ceil(height)
                footerText.draw(with: CGRect(x: inset, y: bottom, width: width, height: height), options: .usesLineFragmentOrigin, context: nil)
                bottom -= 12
            }

            // Shrink the text until everything fits, down to a size that's still readable;
            // past that, the lowest lines are cut.
            let available = bottom - inset
            var fontSize: CGFloat = 30
            var text = attributed(lines, fontSize: fontSize)
            while fontSize > 18, height(of: text, width: width) > available {
                fontSize -= 2
                text = attributed(lines, fontSize: fontSize)
            }
            text.draw(with: CGRect(x: inset, y: inset, width: width, height: available), options: [.usesLineFragmentOrigin, .truncatesLastVisibleLine], context: nil)
        }
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
