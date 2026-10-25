import Foundation

public enum GoldKind: String, CaseIterable, Sendable {
    case gram, quarter, half, full, republic, ounce, carat22, carat18, carat14

    /// Asked about when the request names no kind.
    public static let usual: [GoldKind] = [.gram, .quarter]
}

public struct GoldQuote: Equatable, Sendable {
    public let buying: Double
    public let selling: Double

    public init(buying: Double, selling: Double) {
        self.buying = buying
        self.selling = selling
    }
}

/// Which gold prices a request asks for: "gram altın ne kadar", "çeyrek altın kaç lira", "ons", "gold price".
/// Gold only counts with a price word or a coin named, so "altın oran nedir" stays a question for the model.
public enum GoldQuestion {
    private static let turkishPriceWords = ["kac", "fiyat", "ne kadar", "eder", "deger", "piyasa", "durum", "dustu", "yukseld", "artti", "ucuzla", "pahalan"]
    private static let englishPriceWords = ["price", "prices", "cost", "worth", "much", "rate", "trading"]
    /// Doing something with a price ("…Ahmet'e mesaj at", "…sitesini aç") is another tool's request.
    private static let turkishActions = ["hatirlat", "mesaj", "mail", "posta", "ekle", "kopyala", "uygulama", "site"]
    private static let turkishActionWords: Set<String> = ["ac", "acar", "acsana", "yaz", "not"]
    private static let englishActions: Set<String> = ["remind", "text", "email", "message", "add", "copy", "open", "type", "app"]
    /// Names that mean the kind on their own; the others count only before "altın" or "ayar".
    private static let turkishKinds: [(word: String, kind: GoldKind)] = [
        ("gram", .gram), ("ceyrek", .quarter), ("yarim", .half), ("cumhuriyet", .republic), ("ons", .ounce),
        ("bilezik", .carat22),
    ]
    private static let turkishKindsBeforeGold: [String: GoldKind] = ["tam": .full, "teklik": .full, "ata": .republic]
    private static let carats: [String: GoldKind] = ["22": .carat22, "18": .carat18, "14": .carat14]
    private static let englishKinds: [String: GoldKind] = [
        "gram": .gram, "grams": .gram, "quarter": .quarter, "half": .half, "full": .full, "republic": .republic,
        "ounce": .ounce, "oz": .ounce,
    ]

    /// Nil when the request is not about gold prices; the kinds asked for otherwise, `GoldKind.usual` if none is named.
    public static func kinds(in command: String, language: AssistantLanguage) -> [GoldKind]? {
        let words = TurkishText.folded(command).split(separator: " ").map(String.init)
        var found = language == .english ? englishKinds(words) : turkishKinds(words)
        let caratKinds: Set<GoldKind> = [.carat22, .carat18, .carat14]
        // "22 ayar bilezik gramı" is the carat's gram price, not gram gold as well.
        if found.contains(where: caratKinds.contains) { found.removeAll { $0 == .gram } }
        let mentionsGold = words.contains { $0.hasPrefix("altin") || $0 == "gold" }
            || found.contains { $0 == .ounce || caratKinds.contains($0) }
        let asksPrice = language == .english
            ? words.contains(where: englishPriceWords.contains) || containsPhrase(words, "how", "much")
            : turkishPriceWords.contains { phrase in (" " + words.joined(separator: " ")).contains(" " + phrase) }
        let namesCoin = found.contains { $0 != .gram && $0 != .ounce }
        let acts = language == .english
            ? words.contains(where: englishActions.contains)
            : words.contains { word in turkishActionWords.contains(word) || turkishActions.contains(where: word.hasPrefix) }
        guard asksPrice || namesCoin, mentionsGold, !acts else { return nil }
        return found.isEmpty ? GoldKind.usual : found
    }

    private static func turkishKinds(_ words: [String]) -> [GoldKind] {
        var kinds: [GoldKind] = []
        for (index, word) in words.enumerated() {
            let next = index + 1 < words.count ? words[index + 1] : ""
            let kind = turkishKinds.first { $0.word == "ons" ? word == "ons" : word.hasPrefix($0.word) }?.kind
                ?? (next.hasPrefix("altin") ? turkishKindsBeforeGold[word] : nil)
                ?? (next.hasPrefix("ayar") ? carats[word] : nil)
            if let kind, !kinds.contains(kind) { kinds.append(kind) }
        }
        return kinds
    }

    private static func englishKinds(_ words: [String]) -> [GoldKind] {
        var kinds: [GoldKind] = []
        for (index, word) in words.enumerated() {
            let next = index + 1 < words.count ? words[index + 1] : ""
            let kind = englishKinds[word] ?? (["carat", "karat", "k"].contains(next) ? carats[word] : nil)
                ?? (word.hasSuffix("k") ? carats[String(word.dropLast())] : nil)
            if let kind, !kinds.contains(kind) { kinds.append(kind) }
        }
        return kinds
    }

    private static func containsPhrase(_ words: [String], _ first: String, _ second: String) -> Bool {
        zip(words, words.dropFirst()).contains { $0 == first && $1 == second }
    }
}

/// Reads the gold sources: finans.truncgil.com (primary), Altınkaynak and gold-api.com (fallbacks).
public enum GoldPriceParser {
    private static let truncgilKeys: [GoldKind: String] = [
        .gram: "gram-altin", .quarter: "ceyrek-altin", .half: "yarim-altin", .full: "tam-altin",
        .republic: "cumhuriyet-altini", .ounce: "ons", .carat22: "22-ayar-bilezik", .carat18: "18-ayar-altin",
        .carat14: "14-ayar-altin",
    ]
    /// Altınkaynak has no ounce and lists 22 carat only as scrap.
    private static let altinkaynakCodes: [String: GoldKind] = [
        "GA": .gram, "C": .quarter, "Y": .half, "T": .full, "A_T": .republic, "18": .carat18, "14": .carat14,
    ]

    /// today.json writes "Alış"/"Satış" as Turkish-formatted text; its v4 uses "Buying"/"Selling" numbers.
    public static func truncgil(_ data: Data) -> [GoldKind: GoldQuote] {
        guard let root = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else { return [:] }
        var quotes: [GoldKind: GoldQuote] = [:]
        for (kind, key) in truncgilKeys {
            guard let entry = root[key] as? [String: Any],
                  let quote = quote(buying: entry["Alış"] ?? entry["Buying"], selling: entry["Satış"] ?? entry["Selling"])
            else { continue }
            quotes[kind] = quote
        }
        return quotes
    }

    public static func altinkaynak(_ data: Data) -> [GoldKind: GoldQuote] {
        guard let entries = try? JSONSerialization.jsonObject(with: data) as? [[String: Any]] else { return [:] }
        var quotes: [GoldKind: GoldQuote] = [:]
        for entry in entries {
            guard let code = entry["Kod"] as? String, let kind = altinkaynakCodes[code], quotes[kind] == nil,
                  let quote = quote(buying: entry["Alis"], selling: entry["Satis"]) else { continue }
            quotes[kind] = quote
        }
        return quotes
    }

    /// gold-api.com gives a single ounce price in dollars.
    public static func ounce(_ data: Data) -> GoldQuote? {
        guard let root = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              (root["symbol"] as? String) == "XAU", (root["currency"] as? String) ?? "USD" == "USD",
              let price = PriceNumber.parse(root["price"]), price > 0 else { return nil }
        return GoldQuote(buying: price, selling: price)
    }

    private static func quote(buying: Any?, selling: Any?) -> GoldQuote? {
        guard let buying = PriceNumber.parse(buying), let selling = PriceNumber.parse(selling), buying > 0, selling > 0
        else { return nil }
        return GoldQuote(buying: buying, selling: selling)
    }
}

public enum GoldReport {
    /// Buying and selling for one kind; selling prices for several. Nil when none of `kinds` has a price.
    public static func text(_ quotes: [GoldKind: GoldQuote], kinds: [GoldKind], language: AssistantLanguage) -> String? {
        let priced = kinds.filter { quotes[$0] != nil }
        guard !priced.isEmpty else { return nil }
        let english = language == .english
        if priced.count == 1, let kind = priced.first, let quote = quotes[kind] {
            let (buying, selling) = (PriceNumber.spoken(quote.buying, language: language), PriceNumber.spoken(quote.selling, language: language))
            if quote.buying == quote.selling {
                return english ? "\(name(kind, language)): \(selling) \(unit(kind, language))."
                    : "\(name(kind, language)) \(selling) \(unit(kind, language))."
            }
            return english ? "\(name(kind, language)): buying \(buying), selling \(selling) \(unit(kind, language))."
                : "\(name(kind, language)) alış \(buying), satış \(selling) \(unit(kind, language))."
        }
        let items = priced.compactMap { kind in
            quotes[kind].map { "\(lowercasedFirst(name(kind, language))) \(PriceNumber.spoken($0.selling, language: language)) \(unit(kind, language))" }
        }.joined(separator: ", ")
        return english ? "Selling prices: \(items)." : "Satış fiyatları: \(items)."
    }

    private static func lowercasedFirst(_ text: String) -> String {
        text.prefix(1).lowercased() + text.dropFirst()
    }

    private static func unit(_ kind: GoldKind, _ language: AssistantLanguage) -> String {
        switch (kind, language) {
        case (.ounce, .english): "dollars"
        case (.ounce, .turkish): "dolar"
        case (_, .english): "lira"
        case (_, .turkish): "lira"
        }
    }

    private static func name(_ kind: GoldKind, _ language: AssistantLanguage) -> String {
        if language == .english {
            return switch kind {
            case .gram: "Gram gold"
            case .quarter: "Quarter gold coin"
            case .half: "Half gold coin"
            case .full: "Full gold coin"
            case .republic: "Republic gold coin"
            case .ounce: "Gold per ounce"
            case .carat22: "22-carat gold per gram"
            case .carat18: "18-carat gold per gram"
            case .carat14: "14-carat gold per gram"
            }
        }
        return switch kind {
        case .gram: "Gram altın"
        case .quarter: "Çeyrek altın"
        case .half: "Yarım altın"
        case .full: "Tam altın"
        case .republic: "Cumhuriyet altını"
        case .ounce: "Ons altın"
        case .carat22: "22 ayar bilezik gramı"
        case .carat18: "18 ayar altın gramı"
        case .carat14: "14 ayar altın gramı"
        }
    }
}
