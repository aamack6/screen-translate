import SwiftUI

/// Shown once on first launch: what the app does, honestly, and the three steps to set it up.
struct OnboardingView: View {
    let onDone: () -> Void

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 20) {
                    Text("Translate any app in one press")
                        .font(.title2.bold())
                    Text("Press a button while looking at any app. ScreenTranslate takes a screenshot, reads the text on this iPhone, and shows the screenshot with the translation over the original text. Close it to go back to where you were.")
                    Text("iOS doesn't let apps draw over other apps, so the translation appears on a copy of your screen, not in the app itself.")
                        .foregroundStyle(.secondary)

                    step(1, "Download the languages", "In the Language section, pick what you read (Japanese is detected automatically) and tap Download languages. Translation then works offline.")
                    step(2, "Make the shortcut", "Follow \"Translate any app in one press\" in the app: Take Screenshot, Translate Screenshot, Quick Look.")
                    step(3, "Put it on a button", "A floating button (AssistiveTouch), the Action Button, Back Tap or Control Center. The setup section shows the steps for each.")

                    Text("Shopping in Japanese? Turn on Explain Japanese shopping terms to get notes on condition, shipping and what's included, each linked to the seller's words.")
                        .font(.callout)
                        .foregroundStyle(.secondary)
                }
                .padding()
            }
            .toolbar {
                Button("Get started", action: onDone)
            }
        }
    }

    private func step(_ number: Int, _ title: String, _ detail: String) -> some View {
        HStack(alignment: .top, spacing: 12) {
            Text("\(number)")
                .font(.headline)
                .frame(width: 28, height: 28)
                .background(Color.accentColor.opacity(0.15), in: Circle())
            VStack(alignment: .leading, spacing: 4) {
                Text(title).font(.headline)
                Text(detail).font(.callout)
            }
        }
    }
}
