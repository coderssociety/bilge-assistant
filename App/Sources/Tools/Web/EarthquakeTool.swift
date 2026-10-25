import AsistanCore
import Foundation
import FoundationModels
import Synchronization

/// AFAD's event service, with Kandilli's list when AFAD fails.
enum EarthquakeFeed {
    struct Result: Sendable {
        let earthquakes: [Earthquake]
        let source: EarthquakeSource
    }

    private static let afadURL = "https://servisnet.afad.gov.tr/apigateway/deprem/apiv2/event/filter"
    /// Kandilli answers only over plain http.
    private static let kandilliURL = URL(string: "http://www.koeri.boun.edu.tr/scripts/lst0.asp")!
    private static let afadLimit = 500

    static func fetch(since start: Date, minimumMagnitude: Double, now: Date = .now) async throws -> Result {
        do {
            return Result(earthquakes: try await afad(since: start, minimumMagnitude: minimumMagnitude, now: now), source: .afad)
        } catch is CancellationError {
            throw CancellationError()
        } catch {
            Log.tools.error("AFAD failed, trying Kandilli: \(String(describing: error), privacy: .public)")
            let all = try await kandilli()
            return Result(earthquakes: all.filter { $0.date >= start && $0.magnitude >= minimumMagnitude }, source: .kandilli)
        }
    }

    private static func afad(since start: Date, minimumMagnitude: Double, now: Date) async throws -> [Earthquake] {
        let format = DateFormatter()
        format.locale = Locale(identifier: "en_US_POSIX")
        format.timeZone = .gmt
        format.dateFormat = "yyyy-MM-dd'T'HH:mm:ss"
        var url = URLComponents(string: afadURL)!
        url.queryItems = [
            .init(name: "start", value: format.string(from: start)),
            // AFAD's dates are UTC; a little slack keeps an event stamped a moment ahead of this clock.
            .init(name: "end", value: format.string(from: now.addingTimeInterval(3600))),
            .init(name: "minmag", value: String(minimumMagnitude)),
            .init(name: "orderby", value: "timedesc"),
            .init(name: "limit", value: String(afadLimit)),
            .init(name: "format", value: "json"),
        ]
        do {
            return try AFADEarthquakes.parse(try await WebFetch.data(from: url.url!))
        } catch is EarthquakeFeedError {
            throw WebFetchError.unreadable
        }
    }

    private static func kandilli() async throws -> [Earthquake] {
        let earthquakes = KandilliEarthquakes.parse(KandilliEarthquakes.text(from: try await WebFetch.data(from: kandilliURL)))
        guard !earthquakes.isEmpty else { throw WebFetchError.unreadable }
        return earthquakes
    }
}

/// Where the user's city (the weather city in Settings) is: a province centre, or Open-Meteo's geocoding
/// for anywhere else.
final class CityLocator: Sendable {
    static let shared = CityLocator()
    private let found = Mutex<[String: EarthquakeReport.Place]>([:])

    private struct Places: Decodable {
        struct Place: Decodable { let name: String; let latitude: Double; let longitude: Double }
        let results: [Place]?
    }

    static var userCity: String {
        UserDefaults.standard.string(forKey: WeatherTool.defaultCityKey)?.trimmingCharacters(in: .whitespaces).nilIfEmpty
            ?? WeatherTool.fallbackCity
    }

    func place(for city: String) async throws -> EarthquakeReport.Place? {
        if let province = TurkishProvinces.find(city) {
            return EarthquakeReport.Place(name: province.name, centre: province.centre)
        }
        let key = TurkishText.folded(city)
        if let known = found.withLock({ $0[key] }) { return known }
        var geocoding = URLComponents(string: "https://geocoding-api.open-meteo.com/v1/search")!
        geocoding.queryItems = [.init(name: "name", value: city), .init(name: "count", value: "1"),
                                .init(name: "language", value: AppLanguage.current.code)]
        guard let result = try await WebFetch.json(Places.self, from: geocoding.url!).results?.first else { return nil }
        let place = EarthquakeReport.Place(name: result.name, centre: GeoPoint(latitude: result.latitude, longitude: result.longitude))
        found.withLock { $0[key] = place }
        return place
    }
}

/// "Son depremler", "İzmir'de deprem var mı", "en son deprem nerede". Routed by rule (`RouteGuard.infoTopic`).
struct EarthquakeTool: RuleRoutedTool {
    static let toolName = "earthquakes"
    let name = toolName
    let description = "Son depremleri söyler: büyüklük, yer, ne kadar önce ve derinlik (AFAD, olmazsa Kandilli)."
    private static let cache = FeedCache<EarthquakeFeed.Result>()
    private static let freshness: TimeInterval = 60

    @Generable
    struct Arguments {
        @Guide(description: "Kullanıcının isteği, olduğu gibi")
        var request: String
    }

    @MainActor
    func claims(_ command: String) -> Bool {
        RouteGuard.infoTopic(command, language: AppLanguage.current) == name
    }

    func arguments(fromCommand command: String) -> Arguments? {
        Arguments(request: command)
    }

    func call(arguments: Arguments) async throws -> String {
        let language = AppLanguage.current
        let request = language == .turkish ? TurkishNumberParser.digitize(arguments.request) : arguments.request
        let query = EarthquakeRequest.query(request, language: language)
        let now = Date.now
        do {
            var home: EarthquakeReport.Place?
            if query.nearUser {
                let city = CityLocator.userCity
                guard let place = try await CityLocator.shared.place(for: city) else {
                    return ToolReply.failure(String(localized: "'\(city)' diye bir yer bulamadım."))
                }
                home = place
            }
            let window = EarthquakeReport(query: query, home: home, source: .afad, now: now, language: language).window
            let entry = try await Self.cache.value(for: "\(query.period)", maxAge: Self.freshness) {
                try await EarthquakeFeed.fetch(since: window.start, minimumMagnitude: 0, now: now)
            }
            let report = EarthquakeReport(query: query, home: home, source: entry.value.source, now: now, language: language)
            return entry.stalenessNote + report.text(for: entry.value.earthquakes)
        } catch {
            return ToolReply.failure(String(localized: "Deprem bilgisi alınamadı. \(error.localizedDescription)"))
        }
    }
}
