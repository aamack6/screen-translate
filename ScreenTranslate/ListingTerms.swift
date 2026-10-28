import Foundation

/// Words in Japanese marketplace listings that change what you're actually buying.
/// Machine translation often softens or drops them, so they're flagged separately.
enum ListingTerms {
    struct Term {
        let words: [String]
        let meaning: String
    }

    static let terms: [Term] = [
        Term(words: ["ジャンク"], meaning: "junk: sold as-is, may be broken or incomplete, usually no returns"),
        Term(words: ["傷あり", "キズあり", "傷有り", "キズ有り"], meaning: "has scratches or damage"),
        Term(words: ["やや傷や汚れあり"], meaning: "some scratches or marks (seller's condition grade)"),
        Term(words: ["傷や汚れあり"], meaning: "scratches or marks (seller's condition grade)"),
        Term(words: ["全体的に状態が悪い"], meaning: "poor overall condition (seller's condition grade)"),
        Term(words: ["訳あり", "訳有り"], meaning: "has a problem or flaw, read the description"),
        Term(words: ["難あり", "難有り"], meaning: "has a defect"),
        Term(words: ["動作未確認"], meaning: "not tested, may not work"),
        Term(words: ["プレイ用"], meaning: "for play: worn, not collector condition"),
        Term(words: ["開封済み", "開封済"], meaning: "opened"),
        Term(words: ["シュリンクなし", "シュリンク無し"], meaning: "no shrink wrap, may have been opened"),
        Term(words: ["空箱"], meaning: "empty box only"),
        Term(words: ["箱のみ", "ケースのみ", "スリーブのみ"], meaning: "only the box, case or sleeve, not the item"),
        Term(words: ["海外版", "英語版", "韓国版", "中国版", "外国語版"], meaning: "overseas or foreign-language edition, not Japanese"),
        Term(words: ["オリパ"], meaning: "random repack lottery pack, not a sealed product"),
        Term(words: ["福袋"], meaning: "lucky bag: random contents"),
        Term(words: ["まとめ売り"], meaning: "bundle of several items"),
        Term(words: ["バラ売り"], meaning: "sold loose or separately, not sealed"),
        Term(words: ["レプリカ", "コピー品", "非正規品", "プロキシ"], meaning: "replica, copy or proxy: not genuine"),
        Term(words: ["未鑑定"], meaning: "not graded"),
        Term(words: ["ノークレームノーリターン", "NCNR"], meaning: "no complaints, no returns"),
        Term(words: ["送料別"], meaning: "shipping not included"),
        Term(words: ["予約"], meaning: "pre-order or reserved, check before buying"),
    ]

    /// Good-news words, shown without a warning.
    static let reassuring: [Term] = [
        Term(words: ["未開封"], meaning: "unopened"),
        Term(words: ["シュリンク付き", "シュリンク付"], meaning: "still in shrink wrap"),
        Term(words: ["新品"], meaning: "new"),
        Term(words: ["送料無料", "送料込み", "送料込"], meaning: "shipping included"),
        Term(words: ["傷なし", "キズなし"], meaning: "no scratches"),
    ]

    struct Match {
        let word: String
        let meaning: String
        let isWarning: Bool
    }

    static func matches(in text: String) -> [Match] {
        let normalized = text.precomposedStringWithCompatibilityMapping
        var found: [Match] = []
        var covered: [String] = []
        // Longer words first, so 傷なし (no scratches) isn't also reported as 傷あり-style damage
        // and 未開封 isn't reported as 開封済み.
        let all = (terms.map { ($0, true) } + reassuring.map { ($0, false) })
            .flatMap { term, warning in term.words.map { (word: $0, meaning: term.meaning, warning: warning) } }
            .sorted { $0.word.count > $1.word.count }
        for entry in all where normalized.contains(entry.word) {
            if covered.contains(where: { $0.contains(entry.word) }) { continue }
            covered.append(entry.word)
            if !found.contains(where: { $0.meaning == entry.meaning }) {
                found.append(Match(word: entry.word, meaning: entry.meaning, isWarning: entry.warning))
            }
        }
        return found
    }
}
