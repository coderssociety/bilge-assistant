import Foundation

/// The currencies and amount a conversion request names, read from its own (digitized) words: the model
/// once answered "100 Euro kaç para" with a wrong amount and repeated it when corrected.
public enum CurrencyRequest {
    public struct Parsed: Equatable, Sendable {
        /// ISO 4217 codes in the order they were said.
        public let from: String?
        public let to: String?
        public let amount: Double?
    }

    private static let symbols: [Character: String] = ["€": "euro", "$": "dolar", "£": "sterlin", "₺": "lira"]
    private static let twoWordNames: [(first: String, second: String, code: String)] = [
        ("kanada", "dolar", "CAD"), ("canadian", "dollar", "CAD"), ("avustralya", "dolar", "AUD"), ("australian", "dollar", "AUD"),
        ("isvicre", "frang", "CHF"), ("swiss", "franc", "CHF"), ("isvec", "kron", "SEK"), ("swedish", "kron", "SEK"),
        ("norvec", "kron", "NOK"), ("norwegian", "kron", "NOK"), ("danimarka", "kron", "DKK"), ("danish", "kron", "DKK"),
    ]
    private static let namePrefixes: [(prefix: String, code: String)] = [
        ("dolar", "USD"), ("dollar", "USD"), ("usd", "USD"), ("euro", "EUR"), ("avro", "EUR"), ("eur", "EUR"),
        ("sterlin", "GBP"), ("pound", "GBP"), ("gbp", "GBP"), ("lira", "TRY"), ("tl", "TRY"),
        ("frank", "CHF"), ("franc", "CHF"), ("yuan", "CNY"),
    ]
    private static let exactNames: [String: String] = ["yen": "JPY", "japon": "JPY"]
    private static let amount = try! NSRegularExpression(pattern: #"(?<![\d.,])(\d+(?:[.,]\d+)?)(?![\d])"#)

    public static func parse(_ command: String) -> Parsed {
        let spaced = String(command.flatMap { character in symbols[character].map { " \($0) " } ?? String(character) })
        let words = TurkishText.folded(spaced).split(separator: " ").map(String.init)
        let codes = currencies(in: words)
        let asksForLira = containsPhrase(words, "kac", "para")
        let to = codes.count > 1 ? codes[1] : (asksForLira && codes.first != "TRY" ? "TRY" : nil)
        return Parsed(from: codes.first, to: to, amount: number(in: command))
    }

    private static func currencies(in words: [String]) -> [String] {
        var codes: [String] = []
        var index = words.startIndex
        while index < words.endIndex {
            let word = words[index]
            let next = index + 1 < words.endIndex ? words[index + 1] : ""
            if let pair = twoWordNames.first(where: { word.hasPrefix($0.first) && next.hasPrefix($0.second) }) {
                codes.append(pair.code)
                index += 2
                continue
            }
            if let code = exactNames[word] ?? namePrefixes.first(where: { word.hasPrefix($0.prefix) })?.code, codes.last != code {
                codes.append(code)
            }
            index += 1
        }
        return codes
    }

    private static func containsPhrase(_ words: [String], _ first: String, _ second: String) -> Bool {
        zip(words, words.dropFirst()).contains { $0 == first && $1 == second }
    }

    /// "2,5" is two and a half; "1.500" is fifteen hundred.
    private static func number(in text: String) -> Double? {
        let source = text as NSString
        guard let match = amount.firstMatch(in: text, range: NSRange(location: 0, length: source.length)) else { return nil }
        let digits = source.substring(with: match.range(at: 1))
        let isThousands = digits.firstMatch(of: /^\d{1,3}\.\d{3}$/) != nil
        return Double(isThousands ? digits.replacingOccurrences(of: ".", with: "") : digits.replacingOccurrences(of: ",", with: "."))
    }
}
