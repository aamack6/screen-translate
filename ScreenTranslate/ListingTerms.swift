import Foundation

/// Words in Japanese marketplace listings that change what you're actually buying. Machine
/// translation often softens or drops them, so they're explained separately, each note naming
/// the Japanese phrase it comes from.
///
/// The explanations describe what the seller wrote, never whether it's true: "未使用" is the
/// seller's word for unused, not a promise of mint condition, and "正規品" is a claim, not proof.
enum ListingTerms {
    enum Category: String, CaseIterable {
        case condition, damage, contents, quantity, shipping, payment, timing, photos, authenticity, returns, collector

        var label: String {
            switch self {
            case .condition: return "Condition"
            case .damage: return "Damage"
            case .contents: return "What's included"
            case .quantity: return "Quantity"
            case .shipping: return "Shipping"
            case .payment: return "Payment"
            case .timing: return "Timing"
            case .photos: return "Photos"
            case .authenticity: return "Authenticity"
            case .returns: return "Returns"
            case .collector: return "Collector"
            }
        }
    }

    enum Tone {
        /// Something that may make the item worth less than it looks, or the deal riskier.
        case caution
        /// Worth knowing, neither good nor bad.
        case info
        /// The seller says something reassuring.
        case good

        var symbol: String {
            switch self {
            case .caution: return "⚠︎"
            case .info: return "ℹ︎"
            case .good: return "✓"
            }
        }
    }

    struct Term {
        let words: [String]
        let category: Category
        let tone: Tone
        let meaning: String

        init(_ words: [String], _ category: Category, _ tone: Tone, _ meaning: String) {
            self.words = words
            self.category = category
            self.tone = tone
            self.meaning = meaning
        }
    }

    static let terms: [Term] = [
        // Condition grades, as Mercari and Yahoo! Auctions name them. All are the seller's own call.
        Term(["新品、未使用", "新品未使用"], .condition, .good, "new and unused (seller's grade)"),
        Term(["未使用に近い"], .condition, .info, "close to unused (seller's grade): may have been used or handled briefly"),
        Term(["目立った傷や汚れなし"], .condition, .info, "no noticeable scratches or marks (seller's grade): minor wear is still possible"),
        Term(["やや傷や汚れあり"], .condition, .caution, "some scratches or marks (seller's grade)"),
        Term(["傷や汚れあり"], .condition, .caution, "scratches or marks (seller's grade)"),
        Term(["全体的に状態が悪い"], .condition, .caution, "poor overall condition (seller's grade)"),
        Term(["未使用"], .condition, .info, "unused (seller's word): not the same as mint, sealed or flawless"),
        Term(["極美品"], .condition, .info, "excellent condition (seller's opinion, no fixed standard)"),
        Term(["美品"], .condition, .info, "good condition (seller's opinion, no fixed standard)"),
        Term(["新品同様"], .condition, .info, "like new (seller's opinion): it has been used"),
        Term(["中古"], .condition, .info, "used"),
        Term(["新品"], .condition, .good, "new (seller's word)"),
        Term(["未開封"], .condition, .good, "unopened (seller's word)"),
        Term(["シュリンク付き", "シュリンク付"], .condition, .good, "still in shrink wrap (seller's word)"),
        Term(["現状品", "現状渡し"], .condition, .caution, "sold as-is, in its current condition"),
        Term(["ジャンク"], .condition, .caution, "junk: sold as-is, may be broken or incomplete, usually no returns"),
        Term(["訳あり", "訳有り"], .condition, .caution, "has a problem or flaw; read the description"),
        Term(["難あり", "難有り"], .condition, .caution, "has a defect"),
        Term(["動作未確認"], .condition, .caution, "not tested; may not work"),
        Term(["動作不良", "故障"], .condition, .caution, "not working properly or broken"),
        Term(["動作確認済み", "動作確認済"], .condition, .good, "seller says it was tested and works"),

        // Damage the seller discloses.
        Term(["傷あり", "キズあり", "傷有り", "キズ有り"], .damage, .caution, "has scratches"),
        Term(["汚れあり", "汚れ有り"], .damage, .caution, "has dirt or marks"),
        Term(["スレあり", "スレ有り", "擦れあり", "擦れ有り", "擦れ"], .damage, .caution, "scuffs or rubbing wear"),
        Term(["日焼け", "ヤケあり", "ヤケ有り"], .damage, .caution, "sun fading or yellowing"),
        Term(["シミあり", "シミ有り"], .damage, .caution, "stains or spots"),
        Term(["破れあり", "破れ有り"], .damage, .caution, "tear"),
        Term(["割れあり", "割れ有り", "ヒビあり", "ヒビ有り"], .damage, .caution, "crack"),
        Term(["欠けあり", "欠け有り"], .damage, .caution, "chip"),
        Term(["折れあり", "折れ有り", "折り目", "折れ"], .damage, .caution, "crease or bend"),
        Term(["白欠け"], .damage, .caution, "whitening on the edges (cards)"),
        Term(["角折れ", "角潰れ"], .damage, .caution, "bent or dented corners"),
        Term(["箱傷み", "箱潰れ", "箱ダメージ"], .damage, .caution, "damaged box"),
        Term(["潰れ", "凹み", "へこみ"], .damage, .caution, "dent or crush"),
        Term(["喫煙者", "タバコ臭", "臭いあり", "匂いあり"], .damage, .caution, "smoke or other smell"),
        Term(["ペットあり", "ペットを飼って"], .damage, .info, "pets in the seller's home"),
        Term(["傷なし", "キズなし", "傷無し"], .damage, .good, "no scratches (seller's word)"),

        // What's in the box.
        Term(["本体のみ"], .contents, .caution, "main item only: no box, case or accessories"),
        Term(["本体は付属しません", "本体は付属しない", "本体なし", "本体無し"], .contents, .caution, "the main item isn't included"),
        Term(["箱なし", "箱無し"], .contents, .caution, "no box"),
        Term(["空箱", "空箱のみ"], .contents, .caution, "empty box only"),
        Term(["箱のみ", "ケースのみ", "スリーブのみ"], .contents, .caution, "only the box, case or sleeve, not the item"),
        Term(["付属品なし", "付属品無し"], .contents, .caution, "no accessories"),
        Term(["欠品あり", "欠品"], .contents, .caution, "parts or accessories missing"),
        Term(["説明書なし", "説明書無し"], .contents, .caution, "no manual"),
        Term(["開封済み", "開封済"], .contents, .caution, "opened"),
        Term(["シュリンクなし", "シュリンク無し"], .contents, .caution, "no shrink wrap; may have been opened"),
        Term(["完品"], .contents, .good, "complete (seller's word)"),
        Term(["付属品完備", "付属品あり"], .contents, .good, "accessories included (seller's word)"),

        // How many you get.
        Term(["写真の中から", "選べます"], .quantity, .caution, "you pick one option; you don't get every item or variant shown"),
        Term(["1点のみ", "一点のみ"], .quantity, .info, "one item only"),
        Term(["まとめ売り"], .quantity, .info, "bundle of several items"),
        Term(["点セット", "枚セット"], .quantity, .info, "a set: the price is for all the pieces together"),
        Term(["バラ売り"], .quantity, .info, "sold separately or loose, not as a sealed set"),
        Term(["単品"], .quantity, .info, "single item"),
        Term(["他サイトでも出品中", "他サイト出品中", "早い者勝ち"], .quantity, .info, "also listed elsewhere: it may sell before you buy"),
        Term(["ランダム"], .quantity, .caution, "random: you can't choose which one"),
        Term(["オリパ"], .quantity, .caution, "random repack lottery pack, not an official sealed product"),
        Term(["福袋"], .quantity, .caution, "lucky bag: random contents"),

        // Shipping and payment.
        Term(["送料無料", "送料込み", "送料込"], .shipping, .good, "shipping within Japan included"),
        Term(["送料別", "送料別途"], .shipping, .caution, "shipping not included"),
        Term(["着払い"], .shipping, .caution, "buyer pays shipping on delivery"),
        Term(["匿名配送"], .shipping, .info, "anonymous shipping"),
        Term(["海外発送不可", "国内発送のみ"], .shipping, .caution, "ships within Japan only"),
        Term(["代引き不可", "代金引換不可"], .payment, .info, "cash on delivery not accepted"),
        Term(["代引き", "代金引換"], .payment, .info, "cash on delivery"),

        // When it ships.
        Term(["予約"], .timing, .caution, "pre-order or reservation; check the release or shipping date"),
        Term(["発売日"], .timing, .info, "release date"),
        Term(["発送予定", "発送までの日数"], .timing, .info, "estimated time until it ships"),
        Term(["取り寄せ", "お取り寄せ"], .timing, .caution, "ordered from a supplier after you buy; may take longer"),
        Term(["受注生産"], .timing, .caution, "made to order"),
        Term(["入荷待ち"], .timing, .caution, "waiting for stock"),

        // Whether the photos show this item.
        Term(["イメージ画像", "イメージ写真", "画像はイメージ"], .photos, .caution, "stock or sample photo, not the actual item"),
        Term(["公式画像", "サンプル画像"], .photos, .caution, "official or sample photo, not the actual item"),
        Term(["実物写真", "実物の写真"], .photos, .info, "seller says the photos show the actual item"),

        // Genuine or not. Never proof either way.
        Term(["レプリカ", "コピー品", "非正規品", "海賊版"], .authenticity, .caution, "replica, copy or pirated: not genuine"),
        Term(["プロキシ"], .authenticity, .caution, "proxy card: a stand-in, not a genuine card"),
        Term(["ACG"], .authenticity, .caution, "term often used for unofficial or bootleg merchandise; check carefully"),
        Term(["真贋不明", "真贋未確認"], .authenticity, .caution, "authenticity unknown"),
        Term(["鑑定書なし", "鑑定書無し", "保証書なし", "保証書無し"], .authenticity, .caution, "no certificate or warranty card"),
        Term(["展示品", "ディスプレイ品"], .authenticity, .caution, "display item: may have been handled or exposed to light"),
        Term(["正規品", "本物"], .authenticity, .info, "seller says genuine; this is a claim, not verified"),
        Term(["非売品"], .authenticity, .info, "not sold in stores (promo or prize item)"),

        // Returns.
        Term(["ノークレームノーリターン", "ノークレーム・ノーリターン", "NCNR"], .returns, .caution, "no complaints, no returns"),
        Term(["返品不可", "返品不可能"], .returns, .caution, "no returns"),

        // Collectors.
        Term(["海外版", "英語版", "韓国版", "中国版", "外国語版"], .collector, .info, "overseas or foreign-language edition, not Japanese"),
        Term(["プレイ用"], .collector, .caution, "for play: worn, not collector condition"),
        Term(["未鑑定"], .collector, .info, "not graded"),
        Term(["鑑定品", "PSA", "BGS", "CGC"], .collector, .info, "graded by a third party; check the grade and certificate number"),
        Term(["初版"], .collector, .info, "first print"),
        Term(["プロモ"], .collector, .info, "promo"),
    ]

    /// Words after a term that turn it around: 欠品なし is "nothing missing", not "missing parts".
    private static let negations = ["なし", "無し", "ナシ", "ない", "無", "ではありません", "ではない", "じゃない"]

    struct Match {
        let word: String
        let category: Category
        let tone: Tone
        let meaning: String

        var isWarning: Bool { tone == .caution }

        /// "⚠︎ Shipping · 送料別: shipping not included".
        var note: String { "\(tone.symbol) \(category.label) · \(word): \(meaning)" }
    }

    static func matches(in text: String) -> [Match] {
        let normalized = text.precomposedStringWithCompatibilityMapping
        var found: [Match] = []
        var covered: [Range<String.Index>] = []
        // Longer words first, so 傷なし isn't also reported as 傷あり-style damage, 未開封 isn't
        // reported as 開封済み, and 未使用に近い isn't reported as 未使用.
        let all = terms
            .flatMap { term in term.words.map { (word: $0, term: term) } }
            .sorted { $0.word.count > $1.word.count }
        for entry in all {
            var searchStart = normalized.startIndex
            while let range = normalized.range(of: entry.word, range: searchStart..<normalized.endIndex) {
                searchStart = range.upperBound
                if covered.contains(where: { $0.overlaps(range) }) { continue }
                let rest = normalized[range.upperBound...]
                let negated = entry.term.tone == .caution && negations.contains { rest.hasPrefix($0) }
                let negation = negated ? negations.filter { rest.hasPrefix($0) }.max { $0.count < $1.count } ?? "" : ""
                let fullRange = range.lowerBound..<normalized.index(range.upperBound, offsetBy: negation.count)
                covered.append(fullRange)

                let match = negated
                    ? Match(word: entry.word + negation, category: entry.term.category, tone: .good, meaning: "seller says no: \(entry.term.meaning)")
                    : Match(word: entry.word, category: entry.term.category, tone: entry.term.tone, meaning: entry.term.meaning)
                if !found.contains(where: { $0.meaning == match.meaning }) {
                    found.append(match)
                }
                break
            }
        }
        // Cautions first, then by category, so the important ones aren't cut off.
        let order: [Tone] = [.caution, .info, .good]
        return found.sorted {
            let left = order.firstIndex(of: $0.tone)!, right = order.firstIndex(of: $1.tone)!
            if left != right { return left < right }
            return Category.allCases.firstIndex(of: $0.category)! < Category.allCases.firstIndex(of: $1.category)!
        }
    }
}
