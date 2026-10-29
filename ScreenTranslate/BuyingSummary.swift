import Foundation

/// The questions a buyer has about a Japanese listing, answered only from the seller's own words
/// on the screen. Each answer names the Japanese phrase it comes from, and a question with no
/// matching phrase is listed as not found rather than guessed. It summarizes what the listing
/// says; it can't tell whether the seller is right.
struct BuyingSummary {
    struct Topic {
        let question: String
        let categories: [ListingTerms.Category]
        /// Asked about every listing, so its absence is worth pointing out.
        let essential: Bool
    }

    struct Answer {
        let question: String
        let matches: [ListingTerms.Match]
    }

    let answers: [Answer]
    /// Essential questions nothing on the screen answered.
    let notFound: [String]

    static let topics: [Topic] = [
        Topic(question: "What's included", categories: [.contents], essential: true),
        Topic(question: "One item or the whole lot", categories: [.quantity], essential: false),
        Topic(question: "Condition the seller discloses", categories: [.condition, .damage], essential: true),
        Topic(question: "Shipping and payment", categories: [.shipping, .payment], essential: true),
        Topic(question: "Pre-order, photos, authenticity", categories: [.timing, .photos, .authenticity], essential: false),
        Topic(question: "Returns", categories: [.returns], essential: false),
        Topic(question: "Collector details", categories: [.collector], essential: false),
    ]

    /// Nil when nothing on the screen looks like a listing term.
    static func make(from japaneseTexts: [String]) -> BuyingSummary? {
        var all: [ListingTerms.Match] = []
        for text in japaneseTexts {
            for match in ListingTerms.matches(in: text) where !all.contains(where: { $0.word == match.word }) {
                all.append(match)
            }
        }
        guard !all.isEmpty else { return nil }
        var answers: [Answer] = []
        var notFound: [String] = []
        for topic in topics {
            let matches = all.filter { topic.categories.contains($0.category) }
            if !matches.isEmpty {
                answers.append(Answer(question: topic.question, matches: matches))
            } else if topic.essential {
                notFound.append(topic.question.lowercased())
            }
        }
        return BuyingSummary(answers: answers, notFound: notFound)
    }

    /// Plain lines for drawing under a screenshot.
    var lines: [String] {
        var lines = answers.map { answer in
            "\(answer.question): " + answer.matches.map { "\($0.tone.symbol) \($0.word) (\($0.meaning))" }.joined(separator: "; ")
        }
        if !notFound.isEmpty {
            lines.append("Not found on this screen: \(notFound.joined(separator: ", ")). Check the full listing.")
        }
        return lines
    }
}
