import Foundation

public enum Prayer: String, CaseIterable, Sendable {
    case imsak, sunrise, dhuhr, asr, maghrib, isha

    /// The times an adhan is called at; sunrise is not one.
    public static let calls: [Prayer] = [.imsak, .dhuhr, .asr, .maghrib, .isha]
}

/// One day of prayer times, in minutes after local midnight in `timeZone` (the city's).
public struct PrayerDay: Equatable, Sendable {
    public let year: Int
    public let month: Int
    public let day: Int
    public let minutes: [Prayer: Int]
    public let timeZone: TimeZone

    public init(year: Int, month: Int, day: Int, minutes: [Prayer: Int], timeZone: TimeZone) {
        self.year = year
        self.month = month
        self.day = day
        self.minutes = minutes
        self.timeZone = timeZone
    }

    var calendar: Calendar {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = timeZone
        return calendar
    }

    public func date(of prayer: Prayer) -> Date? {
        guard let minutes = minutes[prayer] else { return nil }
        return calendar.date(from: DateComponents(year: year, month: month, day: day, hour: minutes / 60, minute: minutes % 60))
    }

    func isDay(_ date: Date) -> Bool {
        let parts = calendar.dateComponents([.year, .month, .day], from: date)
        return parts.year == year && parts.month == month && parts.day == day
    }
}

/// Reads the Diyanet monthly lists (ezanvakti.emushaf.net) and the Aladhan fallback. Entries that do not
/// parse are skipped, so one bad day does not lose the month.
public enum PrayerTimesParser {
    public static let turkeyTimeZone = TimeZone(identifier: "Europe/Istanbul")!

    private static let diyanetFields: [(String, Prayer)] = [
        ("Imsak", .imsak), ("Gunes", .sunrise), ("Ogle", .dhuhr), ("Ikindi", .asr), ("Aksam", .maghrib), ("Yatsi", .isha),
    ]
    /// Diyanet's imsak is Aladhan's Fajr; Aladhan's own "Imsak" is a precaution ten minutes earlier.
    private static let aladhanFields: [(String, Prayer)] = [
        ("Fajr", .imsak), ("Sunrise", .sunrise), ("Dhuhr", .dhuhr), ("Asr", .asr), ("Maghrib", .maghrib), ("Isha", .isha),
    ]

    /// `/sehirler/2` → the id of the province's city entry.
    public static func cityID(for province: TurkishProvince, in data: Data) -> String? {
        id(matching: province.name, in: data, nameKey: "SehirAdi", idKey: "SehirID")
    }

    /// `/ilceler/{id}` → the district named after the province, which is its centre.
    public static func centreDistrictID(for province: TurkishProvince, in data: Data) -> String? {
        id(matching: province.name, in: data, nameKey: "IlceAdi", idKey: "IlceID")
    }

    public static func diyanetDays(from data: Data) -> [PrayerDay] {
        guard let entries = try? JSONSerialization.jsonObject(with: data) as? [[String: Any]] else { return [] }
        return entries.compactMap { entry in
            guard let date = entry["MiladiTarihKisa"] as? String else { return nil }
            return day(date: date, separator: ".", fields: diyanetFields, values: entry, timeZone: turkeyTimeZone)
        }
    }

    public static func aladhanDay(from data: Data) -> PrayerDay? {
        guard let root = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let payload = root["data"] as? [String: Any], let timings = payload["timings"] as? [String: Any],
              let gregorian = (payload["date"] as? [String: Any])?["gregorian"] as? [String: Any],
              let date = gregorian["date"] as? String else { return nil }
        let zone = ((payload["meta"] as? [String: Any])?["timezone"] as? String).flatMap(TimeZone.init(identifier:)) ?? turkeyTimeZone
        return day(date: date, separator: "-", fields: aladhanFields, values: timings, timeZone: zone)
    }

    private static func id(matching name: String, in data: Data, nameKey: String, idKey: String) -> String? {
        guard let entries = try? JSONSerialization.jsonObject(with: data) as? [[String: Any]] else { return nil }
        let wanted = TurkishText.folded(name)
        let match = entries.first { ($0[nameKey] as? String).map(TurkishText.folded) == wanted }
        return match?[idKey] as? String
    }

    /// `date` is day, month, year: "25.10.2026", "25-10-2026".
    private static func day(date: String, separator: Character, fields: [(String, Prayer)], values: [String: Any],
                            timeZone: TimeZone) -> PrayerDay? {
        let parts = date.split(separator: separator).compactMap { Int($0) }
        guard parts.count == 3 else { return nil }
        var minutes: [Prayer: Int] = [:]
        for (key, prayer) in fields {
            guard let text = values[key] as? String, let value = clockMinutes(text) else { return nil }
            minutes[prayer] = value
        }
        return PrayerDay(year: parts[2], month: parts[1], day: parts[0], minutes: minutes, timeZone: timeZone)
    }

    /// "05:39", or Aladhan's "05:39 (+03)".
    private static func clockMinutes(_ text: String) -> Int? {
        let clock = text.prefix(5).split(separator: ":").compactMap { Int($0) }
        guard clock.count == 2, (0..<24).contains(clock[0]), (0..<60).contains(clock[1]) else { return nil }
        return clock[0] * 60 + clock[1]
    }
}
