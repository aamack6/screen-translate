# ScreenTranslate

An iPhone app that translates the text in a screenshot with one press of the Action Button. It reads Japanese,
Chinese or Korean text, translates it into English or another language, and draws the translation over the original
text. Translation runs on the iPhone with Apple's Vision and Translation frameworks: no account, no API key, no
screenshot ever leaves the phone.

Made for shopping and collecting from Japan:

- **Convert prices** (optional): ¥12,800, 12,800円, 1万2000円, 150元, NT$990 or 25,000원 get an estimate in USD, EUR,
  GBP and other currencies underneath, plus a "with fees" total if you enter extra costs such as a proxy-service fee.
  Exchange rates come from [ExchangeRate-API](https://www.exchangerate-api.com)'s free endpoint, are cached for
  12 hours, and the request contains only a currency code.
- **Explain condition words** (Japanese, on by default): ジャンク, 傷あり, 海外版, オリパ, 空箱 and about 30 other listing
  terms get a plain-English note, and warning terms give the panel an orange border.

This is a rebuild of an earlier ChatGPT-made prototype whose source was lost. It keeps the same design (a Shortcuts
action fed by Take Screenshot) and adds more languages, a history and a cleaner layout engine.

## Requirements

- A Mac with Xcode 26 or later
- An iPhone on iOS 26 or later (the Action Button needs iPhone 15 Pro or newer; any iPhone can run the shortcut)
- An Apple ID. A free one works for testing on your own phone (the app expires after 7 days); the paid Apple
  Developer Program ($99/year) is needed to keep it installed longer and to sell it

## Build and install on your iPhone

1. Clone this repo on the Mac and open `ScreenTranslate.xcodeproj`.
2. Click the ScreenTranslate project, then the ScreenTranslate target, then **Signing & Capabilities**. Choose your
   team. If Xcode says the bundle ID is taken, change `com.aamack6.ScreenTranslate` to something unique.
3. Plug in the iPhone (or pick it from the device list over Wi-Fi), choose it as the run destination, and press Run.
4. The first time, iOS asks you to trust the developer: Settings › General › VPN & Device Management.

If the project won't open, regenerate it with [XcodeGen](https://github.com/yonaskolb/XcodeGen):
`brew install xcodegen && xcodegen generate`.

## Set it up on the phone

1. Open ScreenTranslate, pick the language you read, and tap **Download languages**. Approve Apple's prompt.
2. In the Shortcuts app, make a shortcut called **Screen Translate** with three actions:
   **Take Screenshot** → **Translate Screenshot** (Screenshot = the result of Take Screenshot) → **Quick Look**.
3. Settings › Action Button › Shortcut › Screen Translate.
4. Open any app with Japanese text and press the Action Button.

Tip: share the finished shortcut (Share › Copy iCloud Link) and paste the link into `AppLinks.readyMadeShortcut`
in `ContentView.swift`. The app then shows a one-tap **Add the ready-made shortcut** button.

## How it works

| File | Job |
| --- | --- |
| `TranslateScreenshotIntent.swift` | The **Translate Screenshot** action in Shortcuts |
| `ScreenTranslator.swift` | The pipeline: decode image → find text → group lines → translate → draw |
| `TextRecognizer.swift` | Vision text recognition for the chosen language |
| `TextGeometry.swift` | Coordinate conversion, status-bar filter, joining wrapped lines into paragraphs |
| `Translator.swift` | Apple's on-device Translation (language status and batch translation) |
| `OverlayRenderer.swift` | Draws the English panels; long translations get a number and a footnote under the image |
| `Prices.swift` | Finds prices in the text and fetches/caches exchange rates |
| `ListingTerms.swift` | Japanese marketplace condition words and their meanings |
| `ContentView.swift`, `ResultView.swift` | Setup screen, options, in-app test, history |
| `HistoryStore.swift` | Optional on-device history of the last 30 translations |

Only text in the chosen language's script is replaced, so English, numbers and prices stay as they are.

## Not tested yet

This code was written without a Mac, so it has not been compiled. Expect a few small compile fixes in Xcode the
first time. Known limits: vertical text (manga) is read poorly by Vision; the Shortcuts action can't show Apple's
language download prompt, which is why the app has a Download button.

See [docs/APP_STORE.md](docs/APP_STORE.md) for the path to selling it.
