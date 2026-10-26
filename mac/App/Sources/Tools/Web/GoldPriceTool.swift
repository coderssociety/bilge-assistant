import AsistanCore
import Foundation
import FoundationModels
import Synchronization

/// "Gram altın ne kadar", "çeyrek altın kaç lira", "ons". Routed by rule, or from exchangeRate by the route
/// guard. finans.truncgil.com first; Altınkaynak (coins, gram) and gold-api.com (ounce) fill what it lacks.
/// Prices are kept ten minutes, and an older price is given with its age when no source answers.
struct GoldPriceTool: RuleRoutedTool {
    let name = "goldPrice"
    let description = "Altın fiyatlarını söyler: gram, çeyrek, yarım, tam, cumhuriyet altını ve ons."
    private static let cache = Mutex(TimedCache<String, [GoldKind: GoldQuote]>(lifetime: 10 * 60))
    private static let cacheKey = "gold"

    @Generable
    struct Arguments {
        @Guide(description: "Kullanıcının isteği, olduğu gibi")
        var command: String
    }

    @MainActor
    func claims(_ command: String) -> Bool {
        GoldQuestion.kinds(in: command, language: AppLanguage.current) != nil
    }

    func arguments(fromCommand command: String) -> Arguments? {
        Arguments(command: command)
    }

    func call(arguments: Arguments) async throws -> String {
        let language = AppLanguage.current
        let kinds = GoldQuestion.kinds(in: arguments.command, language: language) ?? GoldKind.usual
        let failure = ToolReply.failure(String(localized: "Altın fiyatlarını şu an alamadım; kaynaklara ulaşılamadı."))
        let now = Date.now
        if let fresh = Self.cache.withLock({ $0.fresh(Self.cacheKey, at: now) }), kinds.allSatisfy({ fresh[$0] != nil }) {
            return GoldReport.text(fresh, kinds: kinds, language: language) ?? failure
        }
        let quotes = await Self.fetch(kinds)
        if !quotes.isEmpty, let text = GoldReport.text(quotes, kinds: kinds, language: language) {
            Self.cache.withLock { $0.store(quotes, for: Self.cacheKey, at: now) }
            return text
        }
        guard let kept = Self.cache.withLock({ $0.any(Self.cacheKey) }),
              let text = GoldReport.text(kept.value, kinds: kinds, language: language) else { return failure }
        return text + SpokenDuration.staleNote(age: now.timeIntervalSince(kept.storedAt), language: language)
    }

    private static func fetch(_ kinds: [GoldKind]) async -> [GoldKind: GoldQuote] {
        var quotes = await readQuotes("https://finans.truncgil.com/today.json", GoldPriceParser.truncgil)
        let missing = kinds.filter { quotes[$0] == nil }
        if missing.contains(where: { $0 != .ounce }) {
            let fallback = await readQuotes("https://static.altinkaynak.com/Gold", GoldPriceParser.altinkaynak)
            quotes.merge(fallback) { primary, _ in primary }
        }
        if missing.contains(.ounce), let ounce = await read("https://api.gold-api.com/price/XAU", GoldPriceParser.ounce) {
            quotes[.ounce] = ounce
        }
        return quotes
    }

    private static func read<T>(_ address: String, _ parse: (Data) -> T?) async -> T? {
        do {
            let parsed = parse(try await WebFetch.data(from: URL(string: address)!))
            if parsed == nil { Log.tools.error("Unreadable gold prices from \(address, privacy: .public)") }
            return parsed
        } catch {
            Log.tools.error("Gold prices from \(address, privacy: .public) failed: \(error.localizedDescription, privacy: .public)")
            return nil
        }
    }

    private static func readQuotes(_ address: String, _ parse: (Data) -> [GoldKind: GoldQuote]) async -> [GoldKind: GoldQuote] {
        let quotes = await read(address) { data -> [GoldKind: GoldQuote]? in
            let quotes = parse(data)
            return quotes.isEmpty ? nil : quotes
        }
        return quotes ?? [:]
    }
}
