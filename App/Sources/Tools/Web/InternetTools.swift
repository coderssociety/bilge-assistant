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
            geocoding.queryItems = [.init(name: "name", value: city), .init(name: "count", value: "1"), .init(name: "language", value: AppLanguage.current.code)]
            guard let place = try await WebFetch.json(Places.self, from: geocoding.url!).results?.first else {
                return ToolReply.failure(String(localized: "'\(city)' diye bir yer bulamadım."))
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
                return WeatherReport.current(city: place.name, temperature: weather.current.temperature_2m, code: weather.current.weather_code,
                                             language: AppLanguage.current)
            }
            let daily = weather.daily
            return WeatherReport.daily(city: place.name, dayName: Self.dayName(offset: day), minimum: daily.temperature_2m_min[day],
                                       maximum: daily.temperature_2m_max[day], code: daily.weather_code[day],
                                       rainChance: daily.precipitation_probability_max[day], language: AppLanguage.current)
        } catch {
            return ToolReply.failure(String(localized: "Hava durumu alınamadı. \(error.localizedDescription)"))
        }
    }

    private static func dayName(offset: Int) -> String {
        switch offset {
        case 0: return String(localized: "bugün")
        case 1: return String(localized: "yarın")
        default:
            let date = Calendar.current.date(byAdding: .day, value: offset, to: .now) ?? .now
            let weekday = date.formatted(.dateTime.weekday(.wide).locale(AppLanguage.locale))
            return AppLanguage.current == .english ? "on \(weekday)" : weekday
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

        /// Spoken name, in the assistant's language.
        var spokenName: String {
            switch self {
            case .lira: String(localized: "lira")
            case .dollar: String(localized: "dolar")
            case .euro: String(localized: "euro")
            case .pound: String(localized: "sterlin")
            case .swissFranc: String(localized: "İsviçre frangı")
            case .yen: String(localized: "yen")
            case .yuan: String(localized: "yuan")
            case .canadianDollar: String(localized: "Kanada doları")
            case .australianDollar: String(localized: "Avustralya doları")
            case .swedishKrona: String(localized: "İsveç kronu")
            case .norwegianKrone: String(localized: "Norveç kronu")
            case .danishKrone: String(localized: "Danimarka kronu")
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

    /// The model fills an unsaid target with lira, as the description tells it to for Turkish users;
    /// in English the dollar (or the euro, when converting dollars) is the expected default.
    func refine(_ arguments: Arguments, command: String) -> Arguments {
        guard AppLanguage.current == .english, arguments.to == .lira else { return arguments }
        let folded = TurkishText.folded(command)
        guard !["lira", "try", "tl", "turkish"].contains(where: { folded.split(separator: " ").contains(Substring($0)) }) else {
            return arguments
        }
        var refined = arguments
        refined.to = arguments.from == .dollar ? .euro : .dollar
        return refined
    }

    private struct Rates: Decodable {
        let date: String
        let rates: [String: Double]
    }

    func call(arguments: Arguments) async throws -> String {
        let target = arguments.from == arguments.to ? Currency.lira : arguments.to
        guard arguments.from != target else {
            return ToolReply.failure(String(localized: "Hangi para birimini çevireceğimi anlayamadım."))
        }
        let amount = max(arguments.amount ?? 1, 0)
        var url = URLComponents(string: "https://api.frankfurter.app/latest")!
        url.queryItems = [.init(name: "from", value: arguments.from.code), .init(name: "to", value: target.code),
                          .init(name: "amount", value: String(amount))]
        do {
            let result = try await WebFetch.json(Rates.self, from: url.url!)
            guard let value = result.rates[target.code] else {
                return ToolReply.failure(String(localized: "Bu kur bulunamadı."))
            }
            let (source, converted) = (Self.format(amount), Self.format(value))
            return String(localized: "\(source) \(arguments.from.spokenName) \(converted) \(target.spokenName).")
        } catch {
            return ToolReply.failure(String(localized: "Döviz kuru alınamadı. \(error.localizedDescription)"))
        }
    }

    private static func format(_ value: Double) -> String {
        value.formatted(.number.precision(.fractionLength(0...2)).locale(AppLanguage.locale))
    }
}

/// "Bu sayfayı özetle" for the page open in the browser, or a given address. The page text is
/// untrusted and only answered by the tool-less session.
struct ReadWebPageTool: AssistantTool {
    let name = "readWebPage"
    let description = "Tarayıcıda açık olan web sayfasını ya da söylenen adresi indirip okur; özetler ya da soruyu yanıtlar."
    let answersWithLanguageModel = true
    let readingLayout: ContinuedReading.Layout? = .text(maxCharacters: BrowserPage.maxCharacters)

    @Generable
    struct Arguments {
        @Guide(description: "Söylenen web adresi, örn. 'ntv.com.tr'; tarayıcıdaki sayfa isteniyorsa boş bırak")
        var address: String?
    }

    func call(arguments: Arguments) async throws -> String {
        do {
            guard let url = try await Self.target(arguments.address) else {
                return ToolReply.failure(String(localized: "Tarayıcıda açık bir sayfa bulamadım."))
            }
            return try await BrowserPage.text(of: url, maxCharacters: .max)
        } catch {
            return ToolReply.failure(error)
        }
    }

    private static func target(_ address: String?) async throws -> URL? {
        if let address = address?.trimmingCharacters(in: .whitespaces).nilIfEmpty {
            let full = address.contains("://") ? address : "https://\(address)"
            return URL(string: full)
        }
        return try await BrowserPage.current(frontmostOnly: false)?.url
    }
}

extension String {
    var nilIfEmpty: String? { isEmpty ? nil : self }
}
