import Foundation

/// A command the assistant runs by itself at a time of day on chosen days ("her gece 21'de hava durumunu söyle").
/// Days are 0 (Monday) to 6 (Sunday).
public struct Routine: Codable, Equatable, Identifiable, Sendable {
    public static let maxCommandCharacters = 200

    public let id: UUID
    public let days: Set<Int>
    public let hour: Int
    public let minute: Int
    public let command: String

    /// nil for a schedule that never comes due or a command that is empty or too long.
    public init?(id: UUID = UUID(), days: Set<Int>, hour: Int, minute: Int, command: String) {
        let command = command.trimmingCharacters(in: .whitespacesAndNewlines)
        guard Self.isValid(days: days, hour: hour, minute: minute), !command.isEmpty,
              command.count <= Self.maxCommandCharacters else { return nil }
        self.id = id
        self.days = days
        self.hour = hour
        self.minute = minute
        self.command = command
    }

    private enum CodingKeys: String, CodingKey {
        case id, days, hour, minute, command
    }

    public init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        let decoded = Routine(id: try container.decode(UUID.self, forKey: .id),
                              days: Set(try container.decode([Int].self, forKey: .days)),
                              hour: try container.decode(Int.self, forKey: .hour),
                              minute: try container.decode(Int.self, forKey: .minute),
                              command: try container.decode(String.self, forKey: .command))
        guard let decoded else {
            throw DecodingError.dataCorruptedError(forKey: .days, in: container, debugDescription: "Invalid routine")
        }
        self = decoded
    }

    public func encode(to encoder: any Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(id, forKey: .id)
        try container.encode(days.sorted(), forKey: .days)
        try container.encode(hour, forKey: .hour)
        try container.encode(minute, forKey: .minute)
        try container.encode(command, forKey: .command)
    }

    private static func isValid(days: Set<Int>, hour: Int, minute: Int) -> Bool {
        !days.isEmpty && days.isSubset(of: RoutineSchedule.everyDay) && (0..<24).contains(hour) && (0..<60).contains(minute)
    }
}

/// When routines come due and how their schedule is said back.
public enum RoutineSchedule {
    public enum PartOfDay: Sendable {
        case morning, noon, evening, night
    }

    public static let everyDay: Set<Int> = Set(0...6)
    public static let weekdays: Set<Int> = Set(0...4)
    public static let weekend: Set<Int> = [5, 6]
    /// A week and a day: enough to reach any chosen day from any moment.
    private static let daysSearched = 8
    private static let turkishDayNames = ["pazartesi", "salı", "çarşamba", "perşembe", "cuma", "cumartesi", "pazar"]
    private static let englishDayNames = ["Monday", "Tuesday", "Wednesday", "Thursday", "Friday", "Saturday", "Sunday"]

    public static func weekday(of date: Date, calendar: Calendar = .current) -> Int {
        (calendar.component(.weekday, from: date) + 5) % 7
    }

    /// The last time the routine was due in (since, until], or nil.
    public static func latestOccurrence(of routine: Routine, after since: Date, upTo until: Date,
                                        calendar: Calendar = .current) -> Date? {
        var day = calendar.date(bySettingHour: routine.hour, minute: routine.minute, second: 0, of: until)
        for _ in 0..<daysSearched {
            guard let candidate = day, candidate > since else { return nil }
            if candidate <= until, routine.days.contains(weekday(of: candidate, calendar: calendar)) { return candidate }
            day = calendar.date(byAdding: .day, value: -1, to: candidate)
        }
        return nil
    }

    /// The first time the routine is due after `after`.
    public static func nextOccurrence(of routine: Routine, after: Date, calendar: Calendar = .current) -> Date? {
        var day = calendar.date(bySettingHour: routine.hour, minute: routine.minute, second: 0, of: after)
        for _ in 0..<daysSearched {
            guard let candidate = day else { return nil }
            if candidate > after, routine.days.contains(weekday(of: candidate, calendar: calendar)) { return candidate }
            day = calendar.date(byAdding: .day, value: 1, to: candidate)
        }
        return nil
    }

    /// Those due in (since, until], each once. A time missed by more than `grace` (the Mac slept, or the app
    /// was closed) is skipped rather than run late.
    public static func due(_ routines: [Routine], after since: Date, upTo until: Date, grace: TimeInterval,
                           calendar: Calendar = .current) -> [Routine] {
        routines.filter { routine in
            guard let moment = latestOccurrence(of: routine, after: since, upTo: until, calendar: calendar) else { return false }
            return until.timeIntervalSince(moment) <= grace
        }
    }

    public static func partOfDay(hour: Int) -> PartOfDay {
        switch hour {
        case 5..<12: .morning
        case 12..<17: .noon
        case 17..<21: .evening
        default: .night
        }
    }

    public static func sorted(_ routines: [Routine]) -> [Routine] {
        routines.sorted {
            ($0.hour, $0.minute, $0.days.min() ?? 7, $0.command) < ($1.hour, $1.minute, $1.days.min() ?? 7, $1.command)
        }
    }

    /// "her gün 21:00'de", "hafta içi her gün 07:00'de", "pazartesi ve çarşamba günleri 08:30'da";
    /// "every day at 21:00", "on weekdays at 07:00", "on Mondays and Wednesdays at 08:30".
    public static func describe(days: Set<Int>, hour: Int, minute: Int, language: AssistantLanguage) -> String {
        if language == .english {
            return "\(englishDays(days)) at " + String(format: "%02d:%02d", hour, minute)
        }
        return "\(turkishDays(days)) \(TurkishGrammar.timeLocative(hour: hour, minute: minute))"
    }

    /// "her gün 21:00'de “hava durumunu söyle”", "every day at 21:00, “tell me the weather”".
    public static func describe(_ routine: Routine, language: AssistantLanguage) -> String {
        let schedule = describe(days: routine.days, hour: routine.hour, minute: routine.minute, language: language)
        return language == .english ? "\(schedule), “\(routine.command)”" : "\(schedule) “\(routine.command)”"
    }

    private static func turkishDays(_ days: Set<Int>) -> String {
        switch days {
        case everyDay: return "her gün"
        case weekdays: return "hafta içi her gün"
        case weekend: return "hafta sonları"
        default:
            let names = days.sorted().map { turkishDayNames[$0] }
            return names.count == 1 ? "her " + names[0] : joined(names, conjunction: "ve") + " günleri"
        }
    }

    private static func englishDays(_ days: Set<Int>) -> String {
        switch days {
        case everyDay: return "every day"
        case weekdays: return "on weekdays"
        case weekend: return "on weekends"
        default: return "on " + joined(days.sorted().map { englishDayNames[$0] + "s" }, conjunction: "and")
        }
    }

    private static func joined(_ names: [String], conjunction: String) -> String {
        guard let last = names.last, names.count > 1 else { return names.first ?? "" }
        return names.dropLast().joined(separator: ", ") + " \(conjunction) \(last)"
    }
}
