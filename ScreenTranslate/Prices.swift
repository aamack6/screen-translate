import Foundation

/// Finds prices such as ¥12,800, 12,800円, 1万2000円, 3.5万円, 150元, NT$990 or 25,000원.
enum PriceParser {
    static func prices(in text: String, language: SourceLanguage) -> [Double] {
        // NFKC turns full-width digits, commas and ￥ into their plain forms.
        let normalized = text.precomposedStringWithCompatibilityMapping
        let patterns: [String]
        switch language {
        case .japanese:
            patterns = [
                #"¥\s*([0-9][0-9,]*)"#,
                #"(?:([0-9]+(?:\.[0-9]+)?)万)?([0-9][0-9,]*)?\s*円"#,
            ]
        case .chineseSimplified:
            patterns = [
                #"[¥]\s*([0-9][0-9,]*(?:\.[0-9]+)?)"#,
                #"(?:([0-9]+(?:\.[0-9]+)?)万)?([0-9][0-9,]*(?:\.[0-9]+)?)?\s*(?:元|块)"#,
            ]
        case .chineseTraditional:
            patterns = [
                #"NT\$\s*([0-9][0-9,]*(?:\.[0-9]+)?)"#,
                #"(?:([0-9]+(?:\.[0-9]+)?)萬)?([0-9][0-9,]*(?:\.[0-9]+)?)?\s*元"#,
            ]
        case .korean:
            patterns = [
                #"₩\s*([0-9][0-9,]*)"#,
                #"(?:([0-9]+(?:\.[0-9]+)?)만)?\s*([0-9][0-9,]*)?\s*원"#,
            ]
        }

        var results: [Double] = []
        let range = NSRange(normalized.startIndex..., in: normalized)
        for (index, pattern) in patterns.enumerated() {
            guard let regex = try? NSRegularExpression(pattern: pattern) else { continue }
            for match in regex.matches(in: normalized, range: range) {
                let value: Double?
                if index == 0 {
                    value = number(group: 1, of: match, in: normalized)
                } else {
                    // Second pattern: an optional "ten thousands" part plus an optional remainder.
                    let tenThousands = number(group: 1, of: match, in: normalized)
                    let rest = number(group: 2, of: match, in: normalized)
                    value = (tenThousands == nil && rest == nil) ? nil : (tenThousands ?? 0) * 10_000 + (rest ?? 0)
                }
                if let value, value > 0 {
                    results.append(value)
                }
            }
        }
        return results
    }

    private static func number(group: Int, of match: NSTextCheckingResult, in text: String) -> Double? {
        guard let range = Range(match.range(at: group), in: text) else { return nil }
        return Double(text[range].replacingOccurrences(of: ",", with: ""))
    }
}

/// Daily exchange rates from the free ExchangeRate-API "open access" endpoint (no key, no account).
/// Only the currency code is sent; rates are cached so most translations need no network at all.
enum ExchangeRates {
    static let attributionURL = URL(string: "https://www.exchangerate-api.com")!
    private static let maxAge: TimeInterval = 12 * 60 * 60

    private struct Cached: Codable {
        let rates: [String: Double]
        let fetched: Date
    }

    private struct Response: Decodable {
        let result: String
        let rates: [String: Double]
    }

    /// Rate to multiply an amount in `base` by to get `target`. Uses the cache when it's fresh,
    /// otherwise fetches (waiting at most a few seconds) and falls back to an older cache.
    static func rate(from base: String, to target: String) async -> Double? {
        if base == target { return 1 }
        let cached = load(base)
        if let cached, Date().timeIntervalSince(cached.fetched) < maxAge {
            return cached.rates[target]
        }
        if let fresh = await fetch(base) {
            return fresh.rates[target]
        }
        return cached?.rates[target]
    }

    /// When the rates for `base` were last downloaded, for showing in the app.
    static func lastUpdated(for base: String) -> Date? {
        load(base)?.fetched
    }

    private static func fetch(_ base: String) async -> Cached? {
        guard let url = URL(string: "https://open.er-api.com/v6/latest/\(base)") else { return nil }
        var request = URLRequest(url: url)
        request.timeoutInterval = 4
        guard let (data, _) = try? await URLSession.shared.data(for: request),
              let response = try? JSONDecoder().decode(Response.self, from: data),
              response.result == "success"
        else { return nil }

        let cached = Cached(rates: response.rates, fetched: Date())
        if let encoded = try? JSONEncoder().encode(cached) {
            UserDefaults.standard.set(encoded, forKey: key(base))
        }
        return cached
    }

    private static func load(_ base: String) -> Cached? {
        guard let data = UserDefaults.standard.data(forKey: key(base)) else { return nil }
        return try? JSONDecoder().decode(Cached.self, from: data)
    }

    private static func key(_ base: String) -> String { "rates.\(base)" }
}
