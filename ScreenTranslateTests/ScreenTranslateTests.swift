import XCTest
@testable import ScreenTranslate

/// Checks the parts that don't need a device or a translation model: the shopping-term matcher,
/// the buying summary, price parsing and the word list. OCR and translation quality are checked
/// separately with TestSet/ and a human reader.
final class ListingTermsTests: XCTestCase {
    struct PhraseCase: Decodable {
        let id: String
        let text: String
        let expect: [String]
        let absent: [String]
    }

    func testPhraseFixtures() throws {
        let url = try XCTUnwrap(Bundle(for: Self.self).url(forResource: "listing_phrases", withExtension: "json"))
        let cases = try JSONDecoder().decode([PhraseCase].self, from: Data(contentsOf: url))
        XCTAssertGreaterThan(cases.count, 40)
        for phrase in cases {
            let words = ListingTerms.matches(in: phrase.text).map(\.word)
            for word in phrase.expect {
                XCTAssertTrue(words.contains(word), "\(phrase.id): expected \(word) in \(words)")
            }
            for word in phrase.absent {
                XCTAssertFalse(words.contains(word), "\(phrase.id): didn't expect \(word) in \(words)")
            }
        }
    }

    func testNegationTurnsCautionIntoGood() {
        let match = ListingTerms.matches(in: "傷なし").first
        XCTAssertEqual(match?.tone, .good)
        XCTAssertFalse(match?.isWarning ?? true)
    }

    func testCautionsComeFirst() {
        let matches = ListingTerms.matches(in: "未使用です。送料別")
        XCTAssertEqual(matches.first?.isWarning, true)
    }

    func testNoteNamesThePhrase() {
        let note = ListingTerms.matches(in: "送料別").first?.note ?? ""
        XCTAssertTrue(note.contains("送料別"), note)
    }
}

final class BuyingSummaryTests: XCTestCase {
    func testNothingToSummarize() {
        XCTAssertNil(BuyingSummary.make(from: ["こんにちは"]))
    }

    func testAnswersAndGaps() throws {
        let summary = try XCTUnwrap(BuyingSummary.make(from: ["目立った傷や汚れなし", "送料込み"]))
        let questions = summary.answers.map(\.question)
        XCTAssertTrue(questions.contains("Condition the seller discloses"))
        XCTAssertTrue(questions.contains("Shipping and payment"))
        // Nothing says what's in the box, so the summary must say so rather than guess.
        XCTAssertTrue(summary.notFound.contains("what's included"))
        XCTAssertTrue(summary.lines.contains { $0.contains("Not found on this screen") })
    }

    func testRepeatedPhraseCountedOnce() throws {
        let summary = try XCTUnwrap(BuyingSummary.make(from: ["送料込み", "送料込み"]))
        let shipping = summary.answers.first { $0.question == "Shipping and payment" }
        XCTAssertEqual(shipping?.matches.count, 1)
    }
}

final class PriceParserTests: XCTestCase {
    func testJapanesePrices() {
        XCTAssertEqual(PriceParser.prices(in: "¥12,800", language: .japanese), [FoundPrice(amount: 12800, currency: "JPY")])
        XCTAssertEqual(PriceParser.prices(in: "12,800円", language: .japanese), [FoundPrice(amount: 12800, currency: "JPY")])
        XCTAssertEqual(PriceParser.prices(in: "1万2000円", language: .japanese), [FoundPrice(amount: 12000, currency: "JPY")])
        XCTAssertEqual(PriceParser.prices(in: "１２，８００円", language: .japanese), [FoundPrice(amount: 12800, currency: "JPY")])
    }

    func testNoPrice() {
        XCTAssertTrue(PriceParser.prices(in: "10点セット", language: .japanese).isEmpty)
    }
}

final class WordListTests: XCTestCase {
    private var saved: [WordListEntry] = []

    override func setUp() {
        saved = WordList.entries
        WordList.entries = [
            WordListEntry(original: "リーフィア", translation: "Leafeon"),
            WordListEntry(original: "リーフィアex", translation: "Leafeon ex"),
        ]
    }

    override func tearDown() {
        WordList.entries = saved
    }

    func testLongestWordWins() {
        XCTAssertEqual(WordList.substitute(in: "リーフィアexのカード"), "Leafeon exのカード")
    }

    func testExactMatch() {
        XCTAssertEqual(WordList.exactMatch(for: " リーフィア "), "Leafeon")
        XCTAssertNil(WordList.exactMatch(for: "リーフィアのカード"))
    }
}

/// Reads the synthetic listing screenshots (TestSet/make_screenshots.py) with Vision and measures
/// OCR on its own, before any translation: the character error rate of each known line against
/// the closest line Vision found. Prints a table per screenshot. Only the normal-size variant is
/// held to a bar; small, low-resolution and vertical text are measured to show where reading fails.
final class OCRTests: XCTestCase {
    struct Truth: Decodable {
        let file: String
        let variant: String
        let lines: [String]
    }

    func testSyntheticListings() throws {
        let bundle = Bundle(for: Self.self)
        let url = try XCTUnwrap(bundle.url(forResource: "ground_truth", withExtension: "json"))
        let truths = try JSONDecoder().decode([Truth].self, from: Data(contentsOf: url))
        var report: [String] = []
        for truth in truths {
            let name = (truth.file as NSString).deletingPathExtension
            let imageURL = try XCTUnwrap(bundle.url(forResource: name, withExtension: "png"), truth.file)
            let image = try XCTUnwrap(ScreenTranslator.decode(Data(contentsOf: imageURL)))
            let found = try TextRecognizer.recognizeLines(in: image, language: .japanese).map(\.text)
            let rates = truth.lines.map { line in found.map { Self.errorRate(line, $0) }.min() ?? 1 }
            let mean = rates.reduce(0, +) / Double(rates.count)
            let read = rates.filter { $0 <= 0.1 }.count
            report.append(String(format: "%@  CER %.2f  lines read %d/%d", truth.file, mean, read, rates.count))
            if truth.variant == "normal" {
                XCTAssertLessThan(mean, 0.1, "\(truth.file): \(found)")
            }
        }
        let text = report.joined(separator: "\n")
        print(text)
        let attachment = XCTAttachment(string: text)
        attachment.name = "OCR results"
        attachment.lifetime = .keepAlways
        add(attachment)
    }

    /// Edit distance between the two texts, ignoring spaces, divided by the expected length.
    static func errorRate(_ expected: String, _ actual: String) -> Double {
        let a = Array(expected.precomposedStringWithCompatibilityMapping.filter { !$0.isWhitespace })
        let b = Array(actual.precomposedStringWithCompatibilityMapping.filter { !$0.isWhitespace })
        guard !a.isEmpty else { return b.isEmpty ? 0 : 1 }
        var previous = Array(0...b.count)
        for i in 1...a.count {
            var current = [i] + Array(repeating: 0, count: b.count)
            for j in stride(from: 1, through: b.count, by: 1) {
                current[j] = min(previous[j] + 1, current[j - 1] + 1, previous[j - 1] + (a[i - 1] == b[j - 1] ? 0 : 1))
            }
            previous = current
        }
        return min(1, Double(previous[b.count]) / Double(a.count))
    }
}
