import AsistanCore
import Foundation
import FoundationModels
import Synchronization

/// "Akşam ezanı kaçta", "iftara ne kadar var", "yarın imsak kaçta", "bugünkü namaz vakitleri". Routed by rule:
/// the words are unambiguous, and the router prompt stays small. Diyanet's monthly list for the province centre
/// (ezanvakti.emushaf.net) is kept for the month; Aladhan's Diyanet method is the fallback, and the only source
/// for places outside Turkey.
struct PrayerTimesTool: RuleRoutedTool {
    let name = "prayerTimes"
    let description = "Ezan ve namaz vakitlerini söyler: imsak, öğle, ikindi, akşam (iftar), yatsı ve sıradaki vakte kalan süre."
    private static let store = Mutex(Store())

    private struct Store {
        var districtIDs: [Int: String] = [:]
        var days: [String: [PrayerDay]] = [:]
    }

    private enum Place {
        case province(TurkishProvince)
        case other(String)

        var name: String {
            switch self {
            case let .province(province): province.name
            case let .other(name): name
            }
        }

        var key: String { TurkishText.folded(name) }
    }

    @Generable
    struct Arguments {
        @Guide(description: "Kullanıcının isteği, olduğu gibi")
        var command: String
    }

    @MainActor
    func claims(_ command: String) -> Bool {
        PrayerQuestion.parse(command, language: AppLanguage.current, now: .now) != nil
    }

    func arguments(fromCommand command: String) -> Arguments? {
        Arguments(command: command)
    }

    func call(arguments: Arguments) async throws -> String {
        let language = AppLanguage.current
        guard let question = PrayerQuestion.parse(arguments.command, language: language, now: .now) else {
            return ToolReply.failure(String(localized: "Hangi vakti sorduğunu anlayamadım."))
        }
        let place = Self.place(in: arguments.command, language: language)
        let answer = { (days: [PrayerDay]) in PrayerReport.text(question, days: days, city: place.name, now: .now, language: language) }
        if let kept = Self.store.withLock({ $0.days[place.key] }), let text = answer(kept) { return text }
        do {
            let days = try await Self.fetch(place, extraDay: question.dayOffset ?? 0)
            Self.store.withLock { $0.days[place.key] = days }
            return answer(days) ?? ToolReply.failure(String(localized: "O gün için namaz vakitlerini bulamadım."))
        } catch {
            return ToolReply.failure(String(localized: "Namaz vakitleri alınamadı. \(error.localizedDescription)"))
        }
    }

    /// A province said, else another place said ("Berlin'de"), else the default city from Settings.
    private static func place(in command: String, language: AssistantLanguage) -> Place {
        if let province = TurkishProvince.find(in: command) { return .province(province) }
        if let spoken = SpokenPlace.name(in: command, language: language) { return .other(spoken) }
        let city = WeatherTool.defaultCity
        return TurkishProvince.named(city).map(Place.province) ?? .other(city)
    }

    private static func fetch(_ place: Place, extraDay: Int) async throws -> [PrayerDay] {
        if case let .province(province) = place {
            do {
                let days = try await diyanet(province)
                if !days.isEmpty { return days }
                Log.tools.error("Diyanet prayer times empty for \(province.name, privacy: .public)")
            } catch {
                Log.tools.error("Diyanet prayer times failed: \(error.localizedDescription, privacy: .public)")
            }
        }
        return try await aladhan(place, offsets: Array(Set([0, 1, extraDay])).sorted())
    }

    private static func diyanet(_ province: TurkishProvince) async throws -> [PrayerDay] {
        let base = URL(string: "https://ezanvakti.emushaf.net")!
        var districtID = store.withLock { $0.districtIDs[province.plate] }
        if districtID == nil {
            let cities = try await WebFetch.data(from: base.appending(path: "sehirler/2"))
            guard let cityID = PrayerTimesParser.cityID(for: province, in: cities) else { throw WebFetchError.unreadable }
            let districts = try await WebFetch.data(from: base.appending(path: "ilceler/\(cityID)"))
            guard let id = PrayerTimesParser.centreDistrictID(for: province, in: districts) else { throw WebFetchError.unreadable }
            store.withLock { $0.districtIDs[province.plate] = id }
            districtID = id
        }
        let month = try await WebFetch.data(from: base.appending(path: "vakitler/\(districtID ?? "")"))
        return PrayerTimesParser.diyanetDays(from: month)
    }

    /// One request per day: today, tomorrow (for times already past) and the day asked about.
    private static func aladhan(_ place: Place, offsets: [Int]) async throws -> [PrayerDay] {
        let zone = if case .province = place { PrayerTimesParser.turkeyTimeZone } else { TimeZone.current }
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = zone
        var days: [PrayerDay] = []
        for offset in offsets {
            guard let date = calendar.date(byAdding: .day, value: offset, to: .now) else { continue }
            let parts = calendar.dateComponents([.day, .month, .year], from: date)
            let stamp = String(format: "%02d-%02d-%04d", parts.day ?? 1, parts.month ?? 1, parts.year ?? 2000)
            var url: URLComponents
            switch place {
            case let .province(province):
                url = URLComponents(string: "https://api.aladhan.com/v1/timingsByCity/\(stamp)")!
                url.queryItems = [.init(name: "city", value: province.name), .init(name: "country", value: "Turkey")]
            case let .other(name):
                url = URLComponents(string: "https://api.aladhan.com/v1/timingsByAddress/\(stamp)")!
                url.queryItems = [.init(name: "address", value: name)]
            }
            url.queryItems?.append(.init(name: "method", value: "13"))
            guard let day = PrayerTimesParser.aladhanDay(from: try await WebFetch.data(from: url.url!)) else {
                throw WebFetchError.unreadable
            }
            days.append(day)
        }
        return days
    }
}
