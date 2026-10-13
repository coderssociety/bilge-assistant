import AppKit
import AsistanCore
import Foundation
import FoundationModels

struct WeatherTool: AssistantTool {
    let name = "weather"
    let description = "Bir şehrin hava durumunu söyler: şu an, bugün, yarın ya da önümüzdeki günler (Open-Meteo)."
    /// Weather questions without a city use the city set in Settings.
    static let defaultCityKey = "weatherCity"
    static let fallbackCity = "İstanbul"

    @Generable
    struct Arguments {
        @Guide(description: "Şehir adı, eksiz: 'Ankara'da' → 'Ankara'; söylenmediyse boş bırak")
        var city: String?
        @Guide(description: "Kaç gün sonrası: bugün 0, yarın 1; 'şu an' ya da gün söylenmediyse boş bırak", .range(0...6))
        var dayOffset: Int?
    }

    /// The model once filled in "Ankara" for "Bugün hava nasıl"; a city counts only if it was said.
    func refine(_ arguments: Arguments, command: String) -> Arguments {
        guard let city = arguments.city?.trimmingCharacters(in: .whitespaces), !city.isEmpty else { return arguments }
        let stem = String(TurkishText.folded(city).prefix(max(3, city.count - 1)))
        let said = TurkishText.folded(command).split(separator: " ").contains { $0.hasPrefix(stem) }
        var refined = arguments
        if !said { refined.city = nil }
        return refined
    }

    private struct Places: Decodable {
        struct Place: Decodable { let name: String; let latitude: Double; let longitude: Double }
        let results: [Place]?
    }

    private struct Forecast: Decodable {
        struct Current: Decodable {
            let temperature_2m: Double
            let weather_code: Int
        }
        struct Daily: Decodable {
            let time: [String]
            let weather_code: [Int]
            let temperature_2m_max: [Double]
            let temperature_2m_min: [Double]
            let precipitation_probability_max: [Int?]
        }
        let current: Current
        let daily: Daily
    }

    func call(arguments: Arguments) async throws -> String {
        let city = arguments.city?.trimmingCharacters(in: .whitespaces).nilIfEmpty
            ?? UserDefaults.standard.string(forKey: Self.defaultCityKey)?.nilIfEmpty
            ?? Self.fallbackCity
        do {
            var geocoding = URLComponents(string: "https://geocoding-api.open-meteo.com/v1/search")!
            geocoding.queryItems = [.init(name: "name", value: city), .init(name: "count", value: "1"), .init(name: "language", value: "tr")]
            guard let place = try await WebFetch.json(Places.self, from: geocoding.url!).results?.first else {
                return ToolReply.failure("'\(city)' diye bir yer bulamadım.")
            }
            var forecast = URLComponents(string: "https://api.open-meteo.com/v1/forecast")!
            forecast.queryItems = [
                .init(name: "latitude", value: String(place.latitude)), .init(name: "longitude", value: String(place.longitude)),
                .init(name: "current", value: "temperature_2m,weather_code"),
                .init(name: "daily", value: "weather_code,temperature_2m_max,temperature_2m_min,precipitation_probability_max"),
                .init(name: "timezone", value: "auto"), .init(name: "forecast_days", value: "7"),
            ]
            let weather = try await WebFetch.json(Forecast.self, from: forecast.url!)
            guard let day = arguments.dayOffset, day < weather.daily.time.count else {
                return WeatherReport.current(city: place.name, temperature: weather.current.temperature_2m, code: weather.current.weather_code)
            }
            let daily = weather.daily
            return WeatherReport.daily(city: place.name, dayName: Self.dayName(offset: day), minimum: daily.temperature_2m_min[day],
                                       maximum: daily.temperature_2m_max[day], code: daily.weather_code[day],
                                       rainChance: daily.precipitation_probability_max[day])
        } catch {
            return ToolReply.failure("Hava durumu alınamadı. \(error.localizedDescription)")
        }
    }

    private static func dayName(offset: Int) -> String {
        switch offset {
        case 0: return "bugün"
        case 1: return "yarın"
        default:
            let date = Calendar.current.date(byAdding: .day, value: offset, to: .now) ?? .now
            return date.formatted(.dateTime.weekday(.wide).locale(Locale(identifier: "tr_TR")))
        }
    }
}

struct ExchangeRateTool: AssistantTool {
    let name = "exchangeRate"
    let description = "Döviz kurunu ve para çevirisini söyler: 'dolar kaç lira', '100 euro kaç TL' (Avrupa Merkez Bankası kurları)."

    @Generable
    enum Currency {
        case lira, dollar, euro, pound, swissFranc, yen, yuan, canadianDollar, australianDollar, swedishKrona, norwegianKrone, danishKrone

        var code: String {
            switch self {
            case .lira: "TRY"
            case .dollar: "USD"
            case .euro: "EUR"
            case .pound: "GBP"
            case .swissFranc: "CHF"
            case .yen: "JPY"
            case .yuan: "CNY"
            case .canadianDollar: "CAD"
            case .australianDollar: "AUD"
            case .swedishKrona: "SEK"
            case .norwegianKrone: "NOK"
            case .danishKrone: "DKK"
            }
        }

        var turkishName: String {
            switch self {
            case .lira: "lira"
            case .dollar: "dolar"
            case .euro: "euro"
            case .pound: "sterlin"
            case .swissFranc: "İsviçre frangı"
            case .yen: "yen"
            case .yuan: "yuan"
            case .canadianDollar: "Kanada doları"
            case .australianDollar: "Avustralya doları"
            case .swedishKrona: "İsveç kronu"
            case .norwegianKrone: "Norveç kronu"
            case .danishKrone: "Danimarka kronu"
            }
        }
    }

    @Generable
    struct Arguments {
        @Guide(description: "Çevrilen para birimi")
        var from: Currency
        @Guide(description: "Hedef para birimi; söylenmediyse lira")
        var to: Currency
        @Guide(description: "Miktar; söylenmediyse boş bırak")
        var amount: Double?
    }

    private struct Rates: Decodable {
        let date: String
        let rates: [String: Double]
    }

    func call(arguments: Arguments) async throws -> String {
        let target = arguments.from == arguments.to ? Currency.lira : arguments.to
        guard arguments.from != target else { return ToolReply.failure("Hangi para birimini çevireceğimi anlayamadım.") }
        let amount = max(arguments.amount ?? 1, 0)
        var url = URLComponents(string: "https://api.frankfurter.app/latest")!
        url.queryItems = [.init(name: "from", value: arguments.from.code), .init(name: "to", value: target.code),
                          .init(name: "amount", value: String(amount))]
        do {
            let result = try await WebFetch.json(Rates.self, from: url.url!)
            guard let value = result.rates[target.code] else { return ToolReply.failure("Bu kur bulunamadı.") }
            return "\(Self.format(amount)) \(arguments.from.turkishName) \(Self.format(value)) \(target.turkishName)."
        } catch {
            return ToolReply.failure("Döviz kuru alınamadı. \(error.localizedDescription)")
        }
    }

    private static func format(_ value: Double) -> String {
        value.formatted(.number.precision(.fractionLength(0...2)).locale(Locale(identifier: "tr_TR")))
    }
}

struct NewsTool: AssistantTool {
    let name = "news"
    let description = "Son haber başlıklarını okur: gündem, ekonomi, spor, dünya ya da bilim-teknoloji (Anadolu Ajansı)."
    private static let headlineCount = 5

    @Generable
    enum Category {
        case general, economy, sports, world, technology

        var feed: String {
            switch self {
            case .general: "guncel"
            case .economy: "ekonomi"
            case .sports: "spor"
            case .world: "dunya"
            case .technology: "bilim-teknoloji"
            }
        }
    }

    @Generable
    struct Arguments {
        @Guide(description: "Haber konusu; belirtilmediyse general")
        var category: Category
    }

    func call(arguments: Arguments) async throws -> String {
        guard let url = URL(string: "https://www.aa.com.tr/tr/rss/default?cat=\(arguments.category.feed)") else {
            return ToolReply.failure("Haber kaynağı açılamadı.")
        }
        do {
            let headlines = RSSHeadlines.parse(try await WebFetch.data(from: url), limit: Self.headlineCount)
            guard !headlines.isEmpty else { return ToolReply.failure("Haber başlığı bulunamadı.") }
            return "Anadolu Ajansı'ndan son başlıklar. " + headlines.map { $0.hasSuffix(".") ? $0 : $0 + "." }.joined(separator: " ")
        } catch {
            return ToolReply.failure("Haberler alınamadı. \(error.localizedDescription)")
        }
    }
}

/// "Bu sayfayı özetle" for the page open in the browser, or a given address. The page text is
/// untrusted and only answered by the tool-less session.
struct ReadWebPageTool: AssistantTool {
    let name = "readWebPage"
    let description = "Tarayıcıda açık olan web sayfasını ya da söylenen adresi indirip okur; özetler ya da soruyu yanıtlar."
    let answersWithLanguageModel = true
    private static let maxCharacters = 6000

    @Generable
    struct Arguments {
        @Guide(description: "Söylenen web adresi, örn. 'ntv.com.tr'; tarayıcıdaki sayfa isteniyorsa boş bırak")
        var address: String?
    }

    func call(arguments: Arguments) async throws -> String {
        do {
            guard let url = try await Self.target(arguments.address) else {
                return ToolReply.failure("Tarayıcıda açık bir sayfa bulamadım.")
            }
            let html = try await WebFetch.text(from: url)
            let text = HTMLText.extract(html)
            guard !text.isEmpty else { return ToolReply.failure("Sayfada okunabilir yazı yok.") }
            let title = HTMLText.title(html).map { "Başlık: \($0)\n" } ?? ""
            return title + String(text.prefix(Self.maxCharacters))
        } catch {
            return ToolReply.failure(error)
        }
    }

    private static func target(_ address: String?) async throws -> URL? {
        if let address = address?.trimmingCharacters(in: .whitespaces).nilIfEmpty {
            let full = address.contains("://") ? address : "https://\(address)"
            return URL(string: full)
        }
        return try await MainActor.run { try frontBrowserURL() }.flatMap(URL.init(string:))
    }

    /// The front tab of Safari, Chrome, Edge, Brave or Arc, whichever is frontmost.
    @MainActor
    private static func frontBrowserURL() throws -> String? {
        let scripts: [String: String] = [
            "com.apple.Safari": "tell application \"Safari\" to return URL of front document",
            "com.google.Chrome": "tell application \"Google Chrome\" to return URL of active tab of front window",
            "com.microsoft.edgemac": "tell application \"Microsoft Edge\" to return URL of active tab of front window",
            "com.brave.Browser": "tell application \"Brave Browser\" to return URL of active tab of front window",
            "company.thebrowser.Browser": "tell application \"Arc\" to return URL of active tab of front window",
        ]
        let running = NSWorkspace.shared.runningApplications.compactMap(\.bundleIdentifier)
        let front = NSWorkspace.shared.frontmostApplication?.bundleIdentifier
        let candidates = ([front].compactMap { $0 } + running).filter { scripts[$0] != nil }
        guard let browser = candidates.first, let script = scripts[browser] else { return nil }
        return try AppleScriptRunner.run(script).nilIfEmpty
    }
}

extension String {
    var nilIfEmpty: String? { isEmpty ? nil : self }
}
