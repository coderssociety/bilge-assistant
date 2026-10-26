import AsistanCore
import Foundation
import FoundationModels
import Synchronization

/// "Benzin ne kadar", "İzmir'de motorin fiyatı", "LPG kaç lira". Routed by rule. Opet's price API gives gasoline
/// and diesel for the province centre; Petrol Ofisi's price page has every province with LPG and fills in
/// whatever Opet lacks. Prices are kept half an hour, and an older price is given with its age when no source answers.
struct FuelPriceTool: RuleRoutedTool {
    let name = "fuelPrice"
    let description = "Akaryakıt fiyatlarını söyler: benzin, motorin ve LPG, il il."
    private static let cache = Mutex(TimedCache<Int, [FuelKind: Double]>(lifetime: 30 * 60))
    /// Opet lists İstanbul's Asian side under 34 and the European side, the larger, under 934.
    private static let opetCodes = [34: 934]

    @Generable
    struct Arguments {
        @Guide(description: "Kullanıcının isteği, olduğu gibi")
        var command: String
    }

    @MainActor
    func claims(_ command: String) -> Bool {
        FuelQuestion.kinds(in: command, language: AppLanguage.current) != nil
    }

    func arguments(fromCommand command: String) -> Arguments? {
        Arguments(command: command)
    }

    func call(arguments: Arguments) async throws -> String {
        let language = AppLanguage.current
        let kinds = FuelQuestion.kinds(in: arguments.command, language: language) ?? FuelKind.allCases
        guard let province = Self.province(in: arguments.command, language: language) else {
            return ToolReply.failure(String(localized: "Akaryakıt fiyatlarını yalnızca Türkiye'deki iller için söyleyebiliyorum."))
        }
        let failure = ToolReply.failure(String(localized: "Akaryakıt fiyatlarını şu an alamadım; kaynaklara ulaşılamadı."))
        let report = { (prices: [FuelKind: Double]) in FuelReport.text(prices, kinds: kinds, province: province.name, language: language) }
        let now = Date.now
        if let fresh = Self.cache.withLock({ $0.fresh(province.plate, at: now) }), kinds.allSatisfy({ fresh[$0] != nil }) {
            return report(fresh) ?? failure
        }
        let prices = await Self.fetch(kinds, plate: province.plate)
        if !prices.isEmpty, let text = report(prices) {
            Self.cache.withLock { $0.store(prices, for: province.plate, at: now) }
            return text
        }
        guard let kept = Self.cache.withLock({ $0.any(province.plate) }), let text = report(kept.value) else { return failure }
        return text + SpokenDuration.staleNote(age: now.timeIntervalSince(kept.storedAt), language: language)
    }

    /// A province said, else the default city when it is a province. Another place said has no prices.
    private static func province(in command: String, language: AssistantLanguage) -> TurkishProvince? {
        if let said = TurkishProvince.find(in: command) { return said }
        guard SpokenPlace.name(in: command, language: language) == nil else { return nil }
        return TurkishProvince.named(WeatherTool.defaultCity)
    }

    private static func fetch(_ kinds: [FuelKind], plate: Int) async -> [FuelKind: Double] {
        var prices: [FuelKind: Double] = [:]
        if kinds.contains(where: { $0 != .lpg }) {
            var opet = URLComponents(string: "https://api.opet.com.tr/api/fuelprices/prices")!
            opet.queryItems = [.init(name: "ProvinceCode", value: String(opetCodes[plate] ?? plate))]
            prices = await read(opet.url!, FuelPriceParser.opet)
        }
        if kinds.contains(where: { prices[$0] == nil }) {
            let page = await read(URL(string: "https://www.petrolofisi.com.tr/akaryakit-fiyatlari")!) { data in
                FuelPriceParser.petrolOfisi(String(decoding: data, as: UTF8.self), plate: plate)
            }
            prices.merge(page) { primary, _ in primary }
        }
        return prices
    }

    private static func read(_ url: URL, _ parse: (Data) -> [FuelKind: Double]) async -> [FuelKind: Double] {
        do {
            let prices = parse(try await WebFetch.data(from: url))
            if prices.isEmpty { Log.tools.error("No fuel prices in \(url.absoluteString, privacy: .public)") }
            return prices
        } catch {
            Log.tools.error("Fuel prices from \(url.absoluteString, privacy: .public) failed: \(error.localizedDescription, privacy: .public)")
            return [:]
        }
    }
}
