import CoreMedia
import ReplayKit

/// The screen broadcast extension behind live mode. While the user shares their screen with
/// "ScreenTranslate Live", iOS hands this extension every frame, in any app. About once a second
/// it reads the text, keeps what's foreign, and hands it to the app, which translates it and shows
/// it in the floating window.
///
/// Extensions get very little memory (about 50 MB), so translation happens in the app, and only
/// one frame is read at a time.
final class SampleHandler: RPBroadcastSampleHandler {
    private let queue = DispatchQueue(label: "com.aamack6.ScreenTranslate.live.read", qos: .userInitiated)
    private let lock = NSLock()
    private var isReading = false
    private var lastRead = Date.distantPast
    /// Only touched on `queue`.
    private var lastTexts: [String] = []

    override func broadcastStarted(withSetupInfo setupInfo: [String: NSObject]?) {
        LiveShared.write(LiveState(isBroadcasting: true), to: LiveShared.stateURL)
        LiveShared.post(LiveShared.stateNotification)
    }

    override func broadcastFinished() {
        LiveShared.write(LiveState(isBroadcasting: false), to: LiveShared.stateURL)
        LiveShared.write(LiveFrame(date: Date(), blocks: []), to: LiveShared.frameURL)
        LiveShared.post(LiveShared.stateNotification)
    }

    override func processSampleBuffer(_ sampleBuffer: CMSampleBuffer, with sampleBufferType: RPSampleBufferType) {
        guard sampleBufferType == .video, let pixelBuffer = CMSampleBufferGetImageBuffer(sampleBuffer) else { return }
        let config = LiveShared.read(LiveConfig.self, from: LiveShared.configURL)
            ?? LiveConfig(source: nil, target: AppSettings.deviceLanguage)

        lock.lock()
        let ready = !isReading && Date().timeIntervalSince(lastRead) >= config.interval
        if ready {
            isReading = true
            lastRead = Date()
        }
        lock.unlock()
        guard ready else { return }

        let orientation = Self.orientation(of: sampleBuffer)
        queue.async { [weak self] in
            guard let self else { return }
            self.read(pixelBuffer, orientation: orientation, config: config)
            self.lock.lock()
            self.isReading = false
            self.lock.unlock()
        }
    }

    private func read(_ pixelBuffer: CVPixelBuffer, orientation: CGImagePropertyOrientation, config: LiveConfig) {
        guard let lines = try? TextRecognizer.recognizeLines(in: pixelBuffer, orientation: orientation, language: config.source) else { return }
        let size = TextRecognizer.orientedSize(of: pixelBuffer, orientation: orientation)

        // Text already in the user's language is skipped, which includes the floating window's
        // own translations when it sits over the screen.
        var onScreen = lines.filter { !TextGeometry.isInStatusBar($0.rect, imageSize: size) }
        LanguageDetector.assignLanguages(to: &onScreen, source: config.source, target: config.target)
        let foreign = onScreen.filter { $0.language != nil }

        let blocks: [LiveBlock] = TextGeometry.groupIntoBlocks(foreign).compactMap { block in
            guard let language = block.language else { return nil }
            let rect = CGRect(
                x: block.rect.minX / size.width,
                y: block.rect.minY / size.height,
                width: block.rect.width / size.width,
                height: block.rect.height / size.height
            )
            return LiveBlock(text: block.text, language: language, rect: rect)
        }

        // Nothing changed on screen: don't wake the app.
        let texts = blocks.map(\.text)
        guard texts != lastTexts else { return }
        lastTexts = texts

        LiveShared.write(LiveFrame(date: Date(), blocks: blocks), to: LiveShared.frameURL)
        LiveShared.post(LiveShared.frameNotification)
    }

    /// Which way the screen is turned (portrait, or landscape in a game or video).
    private static func orientation(of sampleBuffer: CMSampleBuffer) -> CGImagePropertyOrientation {
        guard let number = CMGetAttachment(sampleBuffer, key: RPVideoSampleOrientationKey as CFString, attachmentModeOut: nil) as? NSNumber,
              let orientation = CGImagePropertyOrientation(rawValue: number.uint32Value) else { return .up }
        return orientation
    }
}
