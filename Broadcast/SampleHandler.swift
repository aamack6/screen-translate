import CoreImage
import CoreMedia
import ImageIO
import Network
import ReplayKit

/// The screen broadcast extension behind live mode. While the user shares their screen with
/// "ScreenTranslate Live", iOS hands this extension every frame, in any app. About once a second
/// it reads the text, keeps what's foreign, and sends it to the app over a loopback connection;
/// the app translates it and shows it in the floating window.
///
/// Extensions get very little memory (about 50 MB), so translation happens in the app, and only
/// one frame is read at a time.
final class SampleHandler: RPBroadcastSampleHandler {
    private let queue = DispatchQueue(label: "com.aamack6.ScreenTranslate.live.read", qos: .userInitiated)
    private let linkQueue = DispatchQueue(label: "com.aamack6.ScreenTranslate.live.link")
    private let lock = NSLock()
    private var isReading = false
    private var lastRead = Date.distantPast
    /// The languages, as the app last sent them. Guarded by `lock`.
    private var config = LiveConfig(source: nil, target: AppSettings.deviceLanguage)
    /// Only touched on `linkQueue`.
    private var link: LiveLink?
    /// Only touched on `queue`.
    private var lastTexts: [String] = []
    /// Only touched on `queue`.
    private lazy var imageContext = CIContext()

    override func broadcastStarted(withSetupInfo setupInfo: [String: NSObject]?) {
        linkQueue.async { self.connectIfNeeded() }
    }

    override func broadcastFinished() {
        linkQueue.sync {
            link?.send(LiveMessage(state: LiveState(isBroadcasting: false), frame: LiveFrame(date: Date(), blocks: [])))
            link?.cancel()
            link = nil
        }
    }

    /// Connects to the app, or reconnects after the app was closed or suspended. Runs on `linkQueue`.
    private func connectIfNeeded() {
        guard link == nil else { return }
        let link = LiveLink.toApp(queue: linkQueue)
        link.onMessage = { [weak self] message in
            guard let self, let config = message.config else { return }
            self.lock.lock()
            self.config = config
            self.lock.unlock()
        }
        link.onClose = { [weak self, weak link] in
            guard let self, self.link === link else { return }
            self.link = nil
            // Send the screen again once a new connection is up.
            self.queue.async { self.lastTexts = [] }
        }
        self.link = link
        link.start()
        link.send(LiveMessage(state: LiveState(isBroadcasting: true)))
    }

    override func processSampleBuffer(_ sampleBuffer: CMSampleBuffer, with sampleBufferType: RPSampleBufferType) {
        guard sampleBufferType == .video, let pixelBuffer = CMSampleBufferGetImageBuffer(sampleBuffer) else { return }
        lock.lock()
        let config = self.config
        let ready = !isReading && Date().timeIntervalSince(lastRead) >= config.interval
        if ready {
            isReading = true
            lastRead = Date()
        }
        lock.unlock()
        guard ready else { return }
        linkQueue.async { self.connectIfNeeded() }

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

        let (thumbnail, aspect) = thumbnail(of: pixelBuffer, orientation: orientation)
        let message = LiveMessage(frame: LiveFrame(date: Date(), blocks: blocks, thumbnail: thumbnail, aspect: aspect))
        linkQueue.async { self.link?.send(message) }
    }

    /// A small, low-quality JPEG of the screen (about 20 KB), so the app can show where each
    /// translation belongs.
    private func thumbnail(of pixelBuffer: CVPixelBuffer, orientation: CGImagePropertyOrientation) -> (Data?, Double?) {
        let image = CIImage(cvPixelBuffer: pixelBuffer).oriented(orientation)
        let extent = image.extent
        guard extent.width > 0 else { return (nil, nil) }
        let scale = 320 / extent.width
        let small = image.transformed(by: CGAffineTransform(scaleX: scale, y: scale))
        let data = imageContext.jpegRepresentation(
            of: small,
            colorSpace: CGColorSpaceCreateDeviceRGB(),
            options: [CIImageRepresentationOption(rawValue: kCGImageDestinationLossyCompressionQuality as String): 0.4]
        )
        return (data, Double(extent.height / extent.width))
    }

    /// Which way the screen is turned (portrait, or landscape in a game or video).
    private static func orientation(of sampleBuffer: CMSampleBuffer) -> CGImagePropertyOrientation {
        guard let number = CMGetAttachment(sampleBuffer, key: RPVideoSampleOrientationKey as CFString, attachmentModeOut: nil) as? NSNumber,
              let orientation = CGImagePropertyOrientation(rawValue: number.uint32Value) else { return .up }
        return orientation
    }
}
