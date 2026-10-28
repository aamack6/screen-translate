# Getting ScreenTranslate onto the App Store

## Before submitting

- [ ] Build runs on a real iPhone and the Action Button shortcut works in at least 10 different apps and games
- [ ] Join the Apple Developer Program ($99/year) and set the team in Xcode
- [ ] Final bundle ID chosen (it can't change after the first upload)
- [ ] Replace the placeholder icon (`Assets.xcassets/AppIcon.appiconset/AppIcon.png`, 1024×1024, no transparency)
- [ ] Ready-made shortcut shared via iCloud link and pasted into `AppLinks.readyMadeShortcut`
- [ ] Privacy policy hosted at a public URL (text in [PRIVACY_POLICY.md](PRIVACY_POLICY.md); a GitHub Pages or
      Notion page is fine)

## App Store Connect

- **Name ideas:** "ScreenTranslate: Action Button", "One-Press Translate". Check the name isn't taken.
- **Category:** Utilities (secondary: Reference)
- **Privacy label:** Data Not Collected. True as long as no analytics or cloud translation is added.
- **Price:** start at $2.99 one-time. Running costs are zero because everything is on-device. Consider a free
  version with a few translations a day and a $3.99 unlock later if downloads are low.
- **Screenshots:** before/after pairs covering different uses: a restaurant menu through the camera, a foreign
  shopping site with converted prices, a game, a group chat, and a document.
- **Review notes:** explain that the app's main feature is a Shortcuts action, give the three-step shortcut, and
  attach a short screen recording. Reviewers reject apps whose purpose they can't find (guideline 4.2), and the
  in-app "Try it" button gives them something to tap without setting up a shortcut.

## Ideas that would make it stand out from Apple's Live Text

- Tap a panel to see the original text, its reading (furigana) and a dictionary lookup
- Yen to dollar conversion next to prices
- Vertical text support for manga (would need a custom recognizer pass on rotated columns)
- A "game mode" that remembers names and terms across screenshots
