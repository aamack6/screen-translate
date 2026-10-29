# Test set

Everything here is synthetic: invented listings drawn with a free font. No real listing, seller
or photo is used.

| What | How to run | Where it runs | What it proves |
| --- | --- | --- | --- |
| Shopping-term rules | `python3 TestSet/check_terms.py` | Any computer | The matcher finds the expected phrases in 49 short phrases and 8 listings, including negation (傷なし) and longest-match cases (空箱のみ, 代引き不可). It runs a Python copy of the rules read from `ListingTerms.swift`. |
| Unit tests | `xcodebuild test -scheme ScreenTranslate -destination 'platform=iOS Simulator,name=iPhone 16'` | Mac, simulator | The real Swift code: listing terms, buying summary, prices, word list. |
| OCR on synthetic screenshots | Same command (`OCRTests`) | Mac, simulator | Vision's character error rate per screenshot, before translation, for normal, small, low-resolution and vertical text. The result is attached to the test run and printed in the log. |
| Translation and notes | `review_sheet.csv` | A person who reads Japanese and English | Whether each translation and each shopping note is right, and whether anything is misleading. |
| Whole experience | The trial plan in the review doc | Real iPhones, real users | Time and taps from capture to understanding, setup without help, return use. |

Simulator and automated checks don't show how the app behaves on an iPhone (the Action Button,
AssistiveTouch, Quick Look, live mode, the online engines). Only a run on a real device does.

## Regenerating the screenshots

```
python3 TestSet/make_screenshots.py            # needs Pillow and IPAGothic
python3 TestSet/make_screenshots.py --font /System/Library/Fonts/ヒラギノ角ゴシック\ W3.ttc   # on a Mac
```

This rewrites `ScreenTranslateTests/Fixtures/Screenshots/` and `TestSet/review_sheet.csv`.

## Filling in the review sheet

1. Translate each screenshot in `ScreenTranslateTests/Fixtures/Screenshots/` with the app (AirDrop
   them to the phone, or use Translate Photo).
2. Copy the app's translation and notes for each line into `app_translation` and `app_notes`.
3. The reader writes their own translation without looking at the app's first, then marks
   `translation_ok` and `notes_ok`, and describes anything that would mislead a buyer.

Count errors separately: text the app misread (OCR), right text but wrong English (translation),
and a wrong or missing shopping note (explanation). Don't make accuracy claims until a reader has
checked a representative sample.
