import Foundation

struct FoundPrice: Equatable {
    let amount: Double
    /// ISO currency code, such as "JPY".
    let currency: String
}

/// Finds prices such as $19.99, 12,50 €, £8, ¥12,800, 12,800円, 1万2000円, 150元, NT$990,
/// 25,000원, ₹499 or 1 200 ₽.
enum PriceParser {
    private static let prefixSymbols: [(String, String)] = [
        ("NT$", "TWD"), ("HK$", "HKD"), ("US$", "USD"), ("A$", "AUD"), ("C$", "CAD"), ("S$", "SGD"), ("R$", "BRL"),
        ("$", "USD"), ("€", "EUR"), ("£", "GBP"), ("¥", "yen"), ("₩", "KRW"), ("₽", "RUB"), ("₴", "UAH"),
        ("฿", "THB"), ("₫", "VND"), ("₹", "INR"), ("₺", "TRY"), ("₱", "PHP"), ("Rp", "IDR"),
    ]

    private static let suffixSymbols: [(String, String)] = [
        ("円", "JPY"), ("元", "yuan"), ("块", "CNY"), ("원", "KRW"), ("€", "EUR"), ("£", "GBP"), ("₽", "RUB"),
        ("руб", "RUB"), ("₴", "UAH"), ("грн", "UAH"), ("บาท", "THB"), ("฿", "THB"), ("₫", "VND"), ("đ", "VND"),
        ("₹", "INR"), ("₺", "TRY"), ("TL", "TRY"), ("zł", "PLN"), ("kr", "SEK"),
        ("USD", "USD"), ("EUR", "EUR"), ("GBP", "GBP"), ("JPY", "JPY"), ("CNY", "CNY"), ("KRW", "KRW"),
    ]

    /// - Parameter language: the text's language, used only to tell what ¥ and 元 mean.
    static func prices(in text: String, language: AppLanguage?) -> [FoundPrice] {
        // NFKC turns full-width digits, commas and ￥ into their plain forms.
        let normalized = text.precomposedStringWithCompatibilityMapping
        let yen = language?.yenCurrency ?? "JPY"
        var found: [(range: NSRange, price: FoundPrice)] = []

        func add(_ range: NSRange, _ amount: Double?, _ code: String) {
            guard let amount, amount > 0 else { return }
            guard !found.contains(where: { NSIntersectionRange($0.range, range).length > 0 }) else { return }
            let currency = code == "yen" ? yen : (code == "yuan" ? (yen == "JPY" ? "CNY" : yen) : code)
            found.append((range, FoundPrice(amount: amount, currency: currency)))
        }

        // Digits with optional thousands groups (12,800 / 1.234 / 1 200) and an optional decimal part.
        let number = #"([0-9]{1,3}(?:[,.\x{00A0}\x{202F} ][0-9]{3})+(?:[.,][0-9]{1,2})?|[0-9]+(?:[.,][0-9]{1,2})?)"#

        // East Asian "ten thousand" amounts first (1万2000円, 3.5万元, 2만 5000원), so the
        // remainder isn't also read as a separate price.
        for (unit, code) in [("[万萬]", "yen"), ("만", "KRW")] {
            let pattern = #"([0-9]+(?:\.[0-9]+)?)\#(unit)\s*([0-9][0-9,]*)?\s*(円|元|원)?"#
            for match in matches(pattern, in: normalized) {
                let tenThousands = Double(group(1, match, normalized) ?? "")
                let rest = Double((group(2, match, normalized) ?? "0").replacingOccurrences(of: ",", with: ""))
                let suffix = group(3, match, normalized)
                guard tenThousands != nil, suffix != nil || code == "KRW" else { continue }
                let currency = suffix == "円" ? "JPY" : (suffix == "元" ? "yuan" : code)
                add(match.range, (tenThousands ?? 0) * 10_000 + (rest ?? 0), currency)
            }
        }

        for (symbol, code) in prefixSymbols {
            let pattern = NSRegularExpression.escapedPattern(for: symbol) + #"\s?"# + number
            for match in matches(pattern, in: normalized) {
                add(match.range, parseNumber(group(1, match, normalized)), code)
            }
        }

        for (symbol, code) in suffixSymbols {
            // Letters-only symbols (TL, kr, USD) need a word boundary so "1 TLC" isn't a price.
            let boundary = symbol.allSatisfy(\.isLetter) && symbol.allSatisfy(\.isASCII) ? #"\b"# : ""
            let pattern = number + #"\s?"# + NSRegularExpression.escapedPattern(for: symbol) + boundary
            for match in matches(pattern, in: normalized) {
                add(match.range, parseNumber(group(1, match, normalized)), code)
            }
        }

        return found.sorted { $0.range.location < $1.range.location }.map(\.price)
    }

    /// Reads "12,800", "1.234,56", "12,50", "1 200" and "19.99" the way people mean them.
    static func parseNumber(_ raw: String?) -> Double? {
        guard var text = raw?.trimmingCharacters(in: .whitespaces) else { return nil }
        text = text.replacingOccurrences(of: "\u{00A0}", with: "")
            .replacingOccurrences(of: "\u{202F}", with: "")
            .replacingOccurrences(of: " ", with: "")

        let lastComma = text.lastIndex(of: ",")
        let lastDot = text.lastIndex(of: ".")
        switch (lastComma, lastDot) {
        case let (comma?, dot?):
            // Both used: whichever comes last is the decimal separator.
            if comma > dot {
                text = text.replacingOccurrences(of: ".", with: "").replacingOccurrences(of: ",", with: ".")
            } else {
                text = text.replacingOccurrences(of: ",", with: "")
            }
        case let (comma?, nil):
            // "12,50" is a decimal; "12,800" and "1,234,567" are thousands.
            let decimals = text.distance(from: comma, to: text.endIndex) - 1
            let commas = text.filter { $0 == "," }.count
            text = (decimals == 2 && commas == 1)
                ? text.replacingOccurrences(of: ",", with: ".")
                : text.replacingOccurrences(of: ",", with: "")
        case let (nil, dot?):
            // "1.234" and "1.234.567" are thousands (European style); "19.99" is a decimal.
            let decimals = text.distance(from: dot, to: text.endIndex) - 1
            let dots = text.filter { $0 == "." }.count
            if dots > 1 || decimals == 3 {
                text = text.replacingOccurrences(of: ".", with: "")
            }
        case (nil, nil):
            break
        }
        return Double(text)
    }

    private static func matches(_ pattern: String, in text: String) -> [NSTextCheckingResult] {
        guard let regex = try? NSRegularExpression(pattern: pattern) else { return [] }
        return regex.matches(in: text, range: NSRange(text.startIndex..., in: text))
    }

    private static func group(_ index: Int, _ match: NSTextCheckingResult, _ text: String) -> String? {
        guard index < match.numberOfRanges, let range = Range(match.range(at: index), in: text) else { return nil }
        return String(text[range])
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
