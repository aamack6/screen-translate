import AVFoundation
import SwiftUI

/// Point the camera at a menu, box or sign and the translations sit on top of the text, following
/// it as the camera moves. Inside the app iOS allows a real overlay, unlike over other apps.
struct LiveCameraView: View {
    @StateObject private var camera = LiveCamera()
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        ZStack {
            CameraPreview(session: camera.session)
                .ignoresSafeArea()

            GeometryReader { geometry in
                let mapping = camera.mapping(to: geometry.size)
                ForEach(camera.panels) { panel in
                    let rect = mapping(panel.rect)
                    Text(panel.text)
                        .font(.system(size: min(max(rect.height * 0.7, 12), 22), weight: .semibold))
                        .foregroundStyle(.black)
                        .padding(.horizontal, 3)
                        .frame(width: max(rect.width, 90), alignment: .leading)
                        .fixedSize(horizontal: false, vertical: true)
                        .background(.white.opacity(0.92), in: RoundedRectangle(cornerRadius: 4))
                        .position(x: rect.minX + max(rect.width, 90) / 2, y: rect.midY)
                }
            }
            .ignoresSafeArea()

            VStack {
                HStack {
                    Button {
                        dismiss()
                    } label: {
                        Image(systemName: "xmark")
                            .font(.headline)
                            .padding(12)
                            .background(.ultraThinMaterial, in: Circle())
                    }
                    .accessibilityLabel("Close")
                    Spacer()
                }
                Spacer()
                if let message = camera.message {
                    Text(message)
                        .font(.footnote)
                        .padding(8)
                        .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 8))
                }
                Button {
                    camera.isFrozen.toggle()
                } label: {
                    Label(camera.isFrozen ? "Resume" : "Hold", systemImage: camera.isFrozen ? "play.fill" : "pause.fill")
                        .font(.headline)
                        .padding(.horizontal, 20)
                        .padding(.vertical, 12)
                        .background(.ultraThinMaterial, in: Capsule())
                }
            }
            .padding()
        }
        .tint(.primary)
        .task { await camera.start() }
        .onDisappear { camera.stop() }
    }
}

struct CameraPanel: Identifiable {
    let id = UUID()
    /// Where the text is in the camera image, 0...1 with a top-left origin.
    let rect: CGRect
    let text: String
}

/// Reads the camera about twice a second and translates the text it finds.
final class LiveCamera: NSObject, ObservableObject, AVCaptureVideoDataOutputSampleBufferDelegate {
    let session = AVCaptureSession()
    @MainActor @Published var panels: [CameraPanel] = []
    @MainActor @Published var message: String?
    /// Holds the current translations still, so they can be read without keeping the phone steady.
    @MainActor @Published var isFrozen = false {
        didSet { frozen.withLock { $0 = isFrozen } }
    }
    /// The camera image's size as the user sees it (portrait).
    @MainActor @Published private var imageSize = CGSize(width: 1080, height: 1920)

    private let queue = DispatchQueue(label: "com.aamack6.ScreenTranslate.camera", qos: .userInitiated)
    private let busy = Locked(false)
    private let frozen = Locked(false)
    private let lastRead = Locked(Date.distantPast)

    @MainActor
    func start() async {
        guard await AVCaptureDevice.requestAccess(for: .video) else {
            message = "Allow camera access in Settings › ScreenTranslate."
            return
        }
        guard session.inputs.isEmpty,
              let device = AVCaptureDevice.default(.builtInWideAngleCamera, for: .video, position: .back),
              let input = try? AVCaptureDeviceInput(device: device) else { return }
        session.beginConfiguration()
        session.sessionPreset = .hd1920x1080
        if session.canAddInput(input) { session.addInput(input) }
        let output = AVCaptureVideoDataOutput()
        output.alwaysDiscardsLateVideoFrames = true
        output.videoSettings = [kCVPixelBufferPixelFormatTypeKey as String: kCVPixelFormatType_32BGRA]
        output.setSampleBufferDelegate(self, queue: queue)
        if session.canAddOutput(output) { session.addOutput(output) }
        session.commitConfiguration()
        let session = session
        queue.async { session.startRunning() }
    }

    func stop() {
        let session = session
        queue.async { session.stopRunning() }
    }

    /// Converts a rect in the camera image (0...1) to the screen, for a preview that fills the
    /// screen and crops the image's overflow.
    @MainActor
    func mapping(to viewSize: CGSize) -> (CGRect) -> CGRect {
        let image = imageSize
        let scale = max(viewSize.width / image.width, viewSize.height / image.height)
        let offset = CGPoint(x: (viewSize.width - image.width * scale) / 2, y: (viewSize.height - image.height * scale) / 2)
        return { rect in
            CGRect(
                x: rect.minX * image.width * scale + offset.x,
                y: rect.minY * image.height * scale + offset.y,
                width: rect.width * image.width * scale,
                height: rect.height * image.height * scale
            )
        }
    }

    func captureOutput(_ output: AVCaptureOutput, didOutput sampleBuffer: CMSampleBuffer, from connection: AVCaptureConnection) {
        guard !frozen.value, !busy.value, Date().timeIntervalSince(lastRead.value) > 0.5,
              let pixelBuffer = CMSampleBufferGetImageBuffer(sampleBuffer) else { return }
        busy.withLock { $0 = true }
        lastRead.withLock { $0 = Date() }

        // The back camera's frames are landscape; held upright, the top of the scene is on the right.
        let orientation = CGImagePropertyOrientation.right
        let size = TextRecognizer.orientedSize(of: pixelBuffer, orientation: orientation)
        let source = AppSettings.sourceLanguage
        guard let lines = try? TextRecognizer.recognizeLines(in: pixelBuffer, orientation: orientation, language: source) else {
            busy.withLock { $0 = false }
            return
        }
        var found = lines
        LanguageDetector.assignLanguages(to: &found, source: source, target: AppSettings.targetLanguage)
        let blocks = TextGeometry.groupIntoBlocks(found.filter { $0.language != nil })

        Task { @MainActor in
            defer { self.busy.withLock { $0 = false } }
            let translations = await TextTranslator.translate(blocks.map(\.text))
            guard !self.isFrozen else { return }
            self.imageSize = size
            self.panels = blocks.compactMap { block in
                guard let text = translations[block.text] else { return nil }
                let rect = CGRect(
                    x: block.rect.minX / size.width, y: block.rect.minY / size.height,
                    width: block.rect.width / size.width, height: block.rect.height / size.height
                )
                return CameraPanel(rect: rect, text: text)
            }
            self.message = self.panels.isEmpty ? "Point the camera at text to translate." : nil
        }
    }
}

/// A value shared between the camera queue and the main thread.
final class Locked<Value>: @unchecked Sendable {
    private var stored: Value
    private let lock = NSLock()

    init(_ value: Value) { stored = value }

    var value: Value {
        lock.lock()
        defer { lock.unlock() }
        return stored
    }

    func withLock(_ body: (inout Value) -> Void) {
        lock.lock()
        body(&stored)
        lock.unlock()
    }
}

private struct CameraPreview: UIViewRepresentable {
    let session: AVCaptureSession

    func makeUIView(context: Context) -> PreviewView {
        let view = PreviewView()
        view.previewLayer.session = session
        view.previewLayer.videoGravity = .resizeAspectFill
        return view
    }

    func updateUIView(_ uiView: PreviewView, context: Context) {}

    final class PreviewView: UIView {
        override class var layerClass: AnyClass { AVCaptureVideoPreviewLayer.self }
        var previewLayer: AVCaptureVideoPreviewLayer { layer as! AVCaptureVideoPreviewLayer }
    }
}
