import ReplayKit
import SwiftUI

/// Live mode: share the screen with ScreenTranslate and a floating window keeps translating
/// whatever is on it, in any app, as you scroll.
struct LiveView: View {
    @ObservedObject private var live = LiveTranslator.shared
    @ObservedObject private var store = Store.shared
    @State private var broadcastPicker = BroadcastPicker()

    var body: some View {
        Form {
            Section {
                LivePreview(layer: live.displayLayer)
                    .aspectRatio(LivePanelRenderer.size.width / LivePanelRenderer.size.height, contentMode: .fit)
                    .frame(maxWidth: 220)
                    .clipShape(RoundedRectangle(cornerRadius: 12))
                    .frame(maxWidth: .infinity)
                    .listRowBackground(Color.clear)
            }

            Section {
                Button {
                    broadcastPicker.show()
                } label: {
                    Label(live.isBroadcasting ? "Stop screen sharing" : "1. Start screen sharing",
                          systemImage: live.isBroadcasting ? "stop.circle" : "record.circle")
                }
                Button {
                    live.toggleFloating()
                } label: {
                    Label(live.isFloating ? "Close the floating window" : "2. Show the floating window",
                          systemImage: "pip")
                }
                .disabled(!live.canFloat && !live.isFloating)
                Text("3. Switch to any app. The window follows what's on your screen and translates it about once a second. Drag it aside, pinch to resize, or press pause.")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            } header: {
                Text("Start")
            } footer: {
                Text("In the sharing sheet, pick ScreenTranslate Live, then Start Broadcast. To stop, tap the red indicator at the top of the screen, or come back here.")
            }

            if !store.isPro {
                Section {
                    Text("\(Int(Usage.liveSecondsRemainingToday / 60)) of \(Usage.freeLiveMinutesPerDay) free live minutes left today")
                } footer: {
                    Text("Pro unlocks unlimited live translation.")
                }
            }

            Section {
                Text("Your screen is read on this iPhone and nothing is recorded, saved or uploaded. iOS shows a red indicator while sharing is on. Text that's already in your language is skipped.")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }
        }
        .navigationTitle("Live mode")
        .onAppear { live.prepare() }
        .background(BroadcastPickerHost(picker: broadcastPicker).frame(width: 1, height: 1).opacity(0.01))
    }
}

/// Shows the floating window's content inside the app; PiP starts from this layer.
private struct LivePreview: UIViewRepresentable {
    let layer: CALayer

    func makeUIView(context: Context) -> LayerView {
        let view = LayerView()
        view.hostedLayer = layer
        return view
    }

    func updateUIView(_ uiView: LayerView, context: Context) {}

    final class LayerView: UIView {
        var hostedLayer: CALayer? {
            didSet {
                oldValue?.removeFromSuperlayer()
                if let hostedLayer { layer.addSublayer(hostedLayer) }
            }
        }

        override func layoutSubviews() {
            super.layoutSubviews()
            hostedLayer?.frame = bounds
        }
    }
}

/// Apple's system button is the only way to start a broadcast. It's kept hidden and pressed
/// from our own button so the screen matches the rest of the app.
final class BroadcastPicker {
    let view: RPSystemBroadcastPickerView = {
        let picker = RPSystemBroadcastPickerView(frame: CGRect(x: 0, y: 0, width: 44, height: 44))
        picker.preferredExtension = LiveShared.broadcastExtensionID
        picker.showsMicrophoneButton = false
        return picker
    }()

    func show() {
        for case let button as UIButton in view.subviews {
            button.sendActions(for: .allTouchEvents)
        }
    }
}

private struct BroadcastPickerHost: UIViewRepresentable {
    let picker: BroadcastPicker

    func makeUIView(context: Context) -> RPSystemBroadcastPickerView { picker.view }
    func updateUIView(_ uiView: RPSystemBroadcastPickerView, context: Context) {}
}
