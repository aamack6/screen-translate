# ScreenTranslate

An iPhone translator for anything on screen or in front of you. Press the Action Button (or Back Tap, or a Control
Center button) in any app, or point the camera at a menu, sign or document, and the translation is drawn right over
the original text. Translation runs on the iPhone with Apple's Vision and Translation frameworks: no account, no API
key, and images never leave the phone.

- **Any direction:** reads 15 languages (English, Spanish, French, German, Italian, Portuguese, Russian, Ukrainian,
  Japanese, Chinese, Korean, Thai, Vietnamese, Arabic) and translates into 20, defaulting to the phone's language.
- **Automatic detection:** each piece of text is checked on its own, so a screen mixing several languages works, and
  text already in your language is left alone.
- **Camera and photos:** translate a photo, screenshot or camera shot from inside the app.
- **Results you can use:** copy all the text, hear any line read aloud, share the image, and keep an optional
  on-device history.
- **Convert prices** (optional): $19.99, 12,50 €, £8, ¥12,800, 1万2000円, NT$990, 25,000원, ₹499 and more get an
  estimate in your currency underneath, plus a "with fees" total if you enter shipping or other extra costs.
  Exchange rates come from [ExchangeRate-API](https://www.exchangerate-api.com)'s free endpoint, are cached for
  12 hours, and the request contains only a currency code.
- **Fair pricing:** 10 free translations a day, then one purchase for unlimited use. No ads, coins or subscription.
- **Wrong language?** Every result shows "Japanese → English"; tap it to translate again from another language.
- **Japanese shopping terms** (on by default when reading Japanese): ジャンク, 傷あり, 海外版, オリパ, 空箱 and about 30
  other listing words get a plain-English note, and warning terms give the panel an orange border.

This is a rebuild of an earlier ChatGPT-made prototype whose source was lost. It keeps the same design (a Shortcuts
action fed by Take Screenshot) and adds the features above and a cleaner layout engine.

## Requirements

- A Mac with Xcode 26 or later
- An iPhone on iOS 26 or later (the Action Button needs iPhone 15 Pro or newer; any iPhone can run the shortcut)
- An Apple ID. A free one works for testing on your own phone (the app expires after 7 days); the paid Apple
  Developer Program ($99/year) is needed to keep it installed longer and to sell it

## Build and install on your iPhone

1. Clone this repo on the Mac and open `ScreenTranslate.xcodeproj`.
2. Click the ScreenTranslate project, then **Signing & Capabilities**, and choose your team for **both** targets:
   ScreenTranslate and ScreenTranslateLive (the live mode extension). Both use the App Group
   `group.com.aamack6.ScreenTranslate`; if Xcode flags it, click the refresh button under App Groups. If the bundle
   ID is taken, change `com.aamack6.ScreenTranslate` everywhere it appears (both targets, the App Group in both
   `Config/*.entitlements` files, and `LiveShared.swift`).
3. Plug in the iPhone (or pick it from the device list over Wi-Fi), choose it as the run destination, and press Run.
4. The first time, iOS asks you to trust the developer: Settings › General › VPN & Device Management.

If the project won't open, regenerate it with [XcodeGen](https://github.com/yonaskolb/XcodeGen):
`brew install xcodegen && xcodegen generate`.

## Set it up on the phone

1. Open ScreenTranslate, check the **To** language, and download the languages you expect to read (Apple asks once
   per language pair).
2. In the Shortcuts app, make a shortcut called **Screen Translate** with three actions:
   **Take Screenshot** → **Translate Screenshot** (Screenshot = the result of Take Screenshot) → **Quick Look**.
3. Put it on a button: Settings › Action Button › Shortcut (iPhone 15 Pro and newer), or on any iPhone
   Settings › Accessibility › Touch › Back Tap › Double Tap, or a Shortcut control in Control Center.
4. Open any app with foreign text and press the button.

### Live mode

Open ScreenTranslate › **Live mode**. Tap **Start screen sharing**, pick **ScreenTranslate Live**, then
**Start Broadcast**. Tap **Show the floating window** and switch to any app: the window keeps translating what's on
screen about once a second. Pause from the window's play/pause button; stop sharing from the red indicator at the
top of the screen.

Tip: share the finished shortcut (Share › Copy iCloud Link) and paste the link into `AppLinks.readyMadeShortcut`
in `ContentView.swift`. The app then shows a one-tap **Add the ready-made shortcut** button.

## How it works

| File | Job |
| --- | --- |
| `TranslateScreenshotIntent.swift` | The **Translate Screenshot** action in Shortcuts |
| `ScreenTranslator.swift` | The pipeline: decode image → find text → group lines → translate → draw |
| `TextRecognizer.swift` | Vision text recognition for the chosen language, or with automatic detection; long joined pages are read in screen-sized slices |
| `ImageStitcher.swift` | Joins screenshots taken while scrolling into one long page, dropping fixed headers and the overlap |
| `LanguageDetector.swift` | Decides per line whether to translate and from which language |
| `TextGeometry.swift` | Coordinate conversion, status-bar filter, joining wrapped lines into paragraphs |
| `Translator.swift` | Apple's on-device Translation (language status and batch translation) |
| `OverlayRenderer.swift` | Draws the translation panels; long translations get a number and a footnote under the image |
| `Prices.swift` | Finds prices in about 20 currencies and fetches/caches exchange rates |
| `ListingTerms.swift` | Japanese marketplace condition words and their meanings |
| `ContentView.swift`, `ResultView.swift` | Photo and camera translation, settings, results (copy, read aloud, share), history |
| `HistoryStore.swift` | Optional on-device history of the last 30 translations |
| `Store.swift` | Free daily allowance and the one-time Pro unlock (StoreKit 2) |
| `Broadcast/SampleHandler.swift` | Live mode extension: reads the shared screen about once a second and passes on foreign text |
| `LiveTranslator.swift`, `LiveView.swift` | Live mode in the app: translates that text and draws it in a Picture-in-Picture window |
| `Shared/` | Code used by both the app and the extension (languages, text reading, live mode file exchange) |

Text already in the target language, numbers and symbols stay as they are.

## Not tested yet

This code was written without a Mac, so it has not been compiled. Expect a few small compile fixes in Xcode the
first time. Known limits: vertical text (manga) is read poorly by Vision; with automatic detection Vision picks one main language per image, so a second script on the same screen may be read less accurately; the Shortcuts action can't show Apple's
language download prompt, which is why the app has a Download button.

Live mode risks to check on a real iPhone: the extension has about 50 MB of memory, and if Vision's accurate reader
goes over it, iOS ends the broadcast (fix: read a scaled-down frame); the floating window needs the app to keep
running in the background, which PiP plus the audio background mode should allow; App Review may ask why the app
declares background audio (answer: Picture in Picture for live translation).

See [docs/APP_STORE.md](docs/APP_STORE.md) for the path to selling it.
