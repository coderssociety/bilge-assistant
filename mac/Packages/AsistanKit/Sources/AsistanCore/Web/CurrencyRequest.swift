import Foundation

/// The currencies and amount a conversion request names, read from its own (digitized) words: the model
/// once answered "100 Euro kaç para" with a wrong amount and repeated it when corrected.
public enum CurrencyRequest {
    public struct Parsed: Equatable, Sendable {
        /// ISO 4217 codes: the currency converted and the one it is converted to.
        public let from: String?
        public let to: String?
        public let amount: Double?
        /// A second currency asked about together with the first: "dolar ve euro kaç lira".
        public let alsoFrom: String?

        init(from: String?, to: String?, amount: Double?, alsoFrom: String? = nil) {
            self.from = from
            self.to = to
            self.amount = amount
            self.alsoFrom = alsoFrom
        }
    }

    private struct Mention {
        let code: String
        let index: Int
        /// What follows the currency name in its word: "ya" in "liraya".
        let ending: String
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
    /// "Liraya", "dolara", "Kanada dolarına": the currency converted to.
    private static let dativeEndings: Set<String> = ["a", "e", "ya", "ye", "na", "ne", "ina", "ine", "una", "une"]
    /// Words just before the currency asked for: "kaç lira", "ne kadar TL", "to euros", "how many euros".
    private static let targetMarkers: Set<String> = ["kac", "kadar", "to", "into", "in", "many"]
    private static let joiners: Set<String> = ["ve", "and"]
    private static let amount = try! NSRegularExpression(pattern: #"(?<![\d.,])(\d+(?:[.,]\d+)*)(?!\d)"#)

    public static func parse(_ command: String) -> Parsed {
        let spaced = String(command.flatMap { character in symbols[character].map { " \($0) " } ?? String(character) })
        let words = TurkishText.folded(spaced).split(separator: " ").map(String.init)
        let mentions = currencies(in: words)
        let target = target(among: mentions, words: words)
        var sources: [String] = []
        for mention in mentions where mention.code != target && !sources.contains(mention.code) {
            sources.append(mention.code)
        }
        let asksForLira = containsPhrase(words, "kac", "para")
        let to = target ?? (asksForLira && sources.first != "TRY" ? "TRY" : nil)
        return Parsed(from: sources.first, to: to, amount: number(in: command), alsoFrom: sources.dropFirst().first)
    }

    /// The currency converted to when the request names one: with a dative ending, right after "kaç" or "to",
    /// lira said after other currencies, or else the second of two unless they are joined ("dolar ve euro").
    private static func target(among mentions: [Mention], words: [String]) -> String? {
        if let dative = mentions.first(where: { dativeEndings.contains($0.ending) }) { return dative.code }
        if let marked = mentions.dropFirst().first(where: { mention in
            words[max(0, mention.index - 2)..<mention.index].contains { targetMarkers.contains($0) }
        }) {
            return marked.code
        }
        guard mentions.count > 1, let last = mentions.last else { return nil }
        if last.code == "TRY" { return last.code }
        let (first, second) = (mentions[0], mentions[1])
        let isJoined = words[(first.index + 1)..<second.index].contains { joiners.contains($0) }
        return isJoined ? nil : second.code
    }

    private static func currencies(in words: [String]) -> [Mention] {
        var mentions: [Mention] = []
        var index = words.startIndex
        while index < words.endIndex {
            let word = words[index]
            let next = index + 1 < words.endIndex ? words[index + 1] : ""
            if let pair = twoWordNames.first(where: { word.hasPrefix($0.first) && next.hasPrefix($0.second) }) {
                mentions.append(Mention(code: pair.code, index: index, ending: String(next.dropFirst(pair.second.count))))
                index += 2
                continue
            }
            let match = exactNames[word].map { (code: $0, ending: "") }
                ?? namePrefixes.first(where: { word.hasPrefix($0.prefix) }).map { (code: $0.code, ending: String(word.dropFirst($0.prefix.count))) }
            if let match, mentions.last?.code != match.code {
                mentions.append(Mention(code: match.code, index: index, ending: match.ending))
            }
            index += 1
        }
        return mentions
    }

    private static func containsPhrase(_ words: [String], _ first: String, _ second: String) -> Bool {
        zip(words, words.dropFirst()).contains { $0 == first && $1 == second }
    }

    /// "2,5" is two and a half; "1.500" fifteen hundred; "2.500,50" and "1.000.000" have thousands groups.
    private static func number(in text: String) -> Double? {
        let source = text as NSString
        guard let match = amount.firstMatch(in: text, range: NSRange(location: 0, length: source.length)) else { return nil }
        let digits = source.substring(with: match.range(at: 1))
        let separators = digits.filter { $0 == "." || $0 == "," }
        guard let last = separators.last else { return Double(digits) }
        let decimal: Character?
        if Set(separators).count > 1 {
            guard separators.dropLast().allSatisfy({ $0 != last }) else { return nil }
            decimal = last
        } else if separators.count > 1 || digits.firstMatch(of: /^\d{1,3}\.\d{3}$/) != nil {
            decimal = nil
        } else {
            decimal = last
        }
        let parts: [Substring] = decimal.map { digits.split(separator: $0) } ?? [Substring(digits)]
        let groups: [Substring] = parts[0].split(omittingEmptySubsequences: false) { $0 == "." || $0 == "," }
        let isGrouped = groups[0].count <= 3 && groups.dropFirst().allSatisfy { $0.count == 3 }
        guard groups.count == 1 || isGrouped else { return nil }
        let fraction = parts.count > 1 ? "." + parts[1] : ""
        return Double(groups.joined() + fraction)
    }
}
