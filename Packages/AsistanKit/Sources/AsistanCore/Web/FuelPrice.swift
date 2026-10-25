import Foundation

public enum FuelKind: String, CaseIterable, Sendable {
    case gasoline, diesel, lpg
}

/// Which pump prices a request asks for: "benzin ne kadar", "İzmir'de motorin fiyatı", "LPG kaç lira",
/// "akaryakıt fiyatları". A fuel word counts only with a price word, so "benzin almayı hatırlat" stays a reminder.
public enum FuelQuestion {
    private static let turkishFuels: [(prefix: String, kind: FuelKind?)] = [
        ("benzin", .gasoline), ("kursunsuz", .gasoline), ("motorin", .diesel), ("mazot", .diesel), ("dizel", .diesel),
        ("diesel", .diesel), ("lpg", .lpg), ("otogaz", .lpg), ("elpiji", .lpg), ("akaryakit", nil), ("yakit", nil),
    ]
    private static let turkishPriceWords = ["kac", "fiyat", "ne kadar", "zam", "indirim", "litre", "ucuzla", "pahalan"]
    private static let turkishActions = ["hatirlat", "unutma", "ekle", "listeme", "yakiyor", "yakar", "harca", "mesaj", "mail", "uygulama"]
    private static let turkishActionWords: Set<String> = ["ac", "acar", "acsana", "yaz", "not"]
    private static let englishFuels: [String: FuelKind?] = [
        "gas": .gasoline, "gasoline": .gasoline, "petrol": .gasoline, "unleaded": .gasoline, "diesel": .diesel,
        "lpg": .lpg, "autogas": .lpg, "fuel": nil,
    ]
    private static let englishPriceWords: Set<String> = ["price", "prices", "cost", "costs", "much", "litre", "liter"]
    private static let englishActions: Set<String> = ["remind", "add", "list", "mileage", "consumption", "bill", "open", "text", "email", "type"]

    /// Nil when the request is not about fuel prices; the kinds asked for otherwise, all of them if none is named.
    public static func kinds(in command: String, language: AssistantLanguage) -> [FuelKind]? {
        let words = TurkishText.folded(command).split(separator: " ").map(String.init)
        let english = language == .english
        let found: [FuelKind?] = english
            ? words.compactMap { englishFuels[$0] }
            : words.compactMap { word in turkishFuels.first { word.hasPrefix($0.prefix) }.map(\.kind) }
        let asksPrice = english
            ? words.contains(where: englishPriceWords.contains)
            : turkishPriceWords.contains { phrase in (" " + words.joined(separator: " ")).contains(" " + phrase) }
        let acts = english
            ? words.contains(where: englishActions.contains)
            : words.contains { word in turkishActionWords.contains(word) || turkishActions.contains(where: word.hasPrefix) }
        guard !found.isEmpty, asksPrice, !acts else { return nil }
        var kinds: [FuelKind] = []
        for case let kind? in found where !kinds.contains(kind) { kinds.append(kind) }
        return kinds.isEmpty ? FuelKind.allCases : kinds
    }
}

/// Reads the fuel sources: Opet's public price API (gasoline and diesel per district) and Petrol Ofisi's
/// price page (every province, with LPG).
public enum FuelPriceParser {
    /// The province centre's district ("MERKEZ", "ANADOLU_Y_MERKEZ"), or the first listed.
    public static func opet(_ data: Data) -> [FuelKind: Double] {
        guard let districts = try? JSONSerialization.jsonObject(with: data) as? [[String: Any]], !districts.isEmpty else { return [:] }
        let centre = districts.first { district in
            (district["districtName"] as? String).map { TurkishText.folded($0).contains("merkez") } ?? false
        } ?? districts[0]
        let products = (centre["prices"] as? [[String: Any]] ?? []).compactMap { product -> (name: String, short: String, price: Double)? in
            guard let name = product["productName"] as? String, let price = PriceNumber.parse(product["amount"]), price > 0 else { return nil }
            return (TurkishText.folded(name), product["productShortName"] as? String ?? "", price)
        }
        var prices: [FuelKind: Double] = [:]
        prices[.gasoline] = products.first { $0.short == "KURS" || $0.name.contains("benzin") }?.price
        prices[.diesel] = products.first { $0.short == "MT_ECO" }?.price
            ?? products.filter { $0.name.contains("motorin") }.map(\.price).min()
        prices[.lpg] = products.first { $0.name.contains("lpg") || $0.name.contains("otogaz") }?.price
        return prices
    }

    private static let row = try! NSRegularExpression(
        pattern: #"<tr[^>]*data-disctrict-id="(\d+)"[^>]*>(.*?)</tr>"#, options: [.dotMatchesLineSeparators])
    private static let header = try! NSRegularExpression(pattern: #"<th(?:\s[^>]*)?>(.*?)</th>"#, options: [.dotMatchesLineSeparators])
    private static let withTax = try! NSRegularExpression(pattern: #"class="with-tax">\s*([\d.,]+)"#)

    /// The page's ids start with the plate code ("03431" is İstanbul's European side, listed first).
    public static func petrolOfisi(_ html: String, plate: Int) -> [FuelKind: Double] {
        let source = html as NSString
        let all = NSRange(location: 0, length: source.length)
        let columns = header.matches(in: html, range: all).map { TurkishText.folded(source.substring(with: $0.range(at: 1))) }
        let prefix = String(format: "%03d", plate)
        guard let match = row.matches(in: html, range: all).first(where: { source.substring(with: $0.range(at: 1)).hasPrefix(prefix) })
        else { return [:] }
        let cells = source.substring(with: match.range(at: 2)).components(separatedBy: "<td").dropFirst()
        var prices: [FuelKind: Double] = [:]
        for (column, cell) in zip(columns, cells) {
            guard let kind = kind(ofColumn: column) else { continue }
            let text = cell as NSString
            guard let value = withTax.firstMatch(in: cell, range: NSRange(location: 0, length: text.length))
                .flatMap({ PriceNumber.parse(text.substring(with: $0.range(at: 1))) }), value > 0 else { continue }
            prices[kind] = value
        }
        return prices
    }

    private static func kind(ofColumn name: String) -> FuelKind? {
        if name.contains("kursunsuz") || name.contains("benzin") { return .gasoline }
        if name.contains("diesel") || name.contains("motorin") { return .diesel }
        if name.contains("otogaz") || name.contains("lpg") { return .lpg }
        return nil
    }
}

public enum FuelReport {
    /// Nil when none of `kinds` has a price; kinds without one are said to be missing.
    public static func text(_ prices: [FuelKind: Double], kinds: [FuelKind], province: String, language: AssistantLanguage) -> String? {
        let priced = kinds.filter { prices[$0] != nil }
        guard !priced.isEmpty else { return nil }
        let english = language == .english
        let items = priced.compactMap { kind in
            prices[kind].map { "\(name(kind, language)) \(PriceNumber.spoken($0, language: language))" }
        }
        let list = items.count > 1
            ? items.dropLast().joined(separator: ", ") + (english ? " and " : " ve ") + (items.last ?? "")
            : items[0]
        let missing = kinds.filter { prices[$0] == nil }.map { name($0, language) }
        let sentence = english
            ? "In \(province), \(list) lira per litre."
            : "\(TurkishGrammar.locative(province)) litre fiyatı \(list) lira."
        guard !missing.isEmpty else { return sentence }
        let names = missing.joined(separator: english ? " and " : " ve ")
        return sentence + (english ? " I couldn't find the \(names) price." : " \(names) fiyatını bulamadım.")
    }

    private static func name(_ kind: FuelKind, _ language: AssistantLanguage) -> String {
        switch (kind, language) {
        case (.gasoline, .english): "gasoline"
        case (.diesel, .english): "diesel"
        case (.lpg, .english): "LPG"
        case (.gasoline, .turkish): "benzin"
        case (.diesel, .turkish): "motorin"
        case (.lpg, .turkish): "LPG"
        }
    }
}
