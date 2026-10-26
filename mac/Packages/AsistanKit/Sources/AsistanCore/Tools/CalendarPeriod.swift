import Foundation

/// Which stretch of the calendar a question asks about: "cuma günü toplantım var mı", "haftaya ne var", "bu ay".
public enum CalendarPeriod: Equatable, Sendable {
    case day(offset: Int)
    /// The next seven days, today included.
    case thisWeek
    /// The next calendar week.
    case nextWeek
    /// From today to the end of the month.
    case thisMonth

    private static let englishWeekdays = ["monday", "tuesday", "wednesday", "thursday", "friday", "saturday", "sunday"]

    public static func parse(_ text: String, language: AssistantLanguage, now: Date, calendar: Calendar = .current) -> CalendarPeriod? {
        let folded = " " + TurkishText.folded(text) + " "
        func says(_ phrases: [String]) -> Bool { phrases.contains { folded.contains(" \($0) ") } }
        if language == .english {
            if says(["this month"]) { return .thisMonth }
            if says(["next week"]), !says(englishWeekdays) { return .nextWeek }
            if says(["this week"]) { return .thisWeek }
            return EnglishTimeParser.dayOffset(in: text, now: now, calendar: calendar).map { .day(offset: $0) }
        }
        if says(["bu ay", "bu ayki", "ay boyunca"]) { return .thisMonth }
        if says(["haftaya", "gelecek hafta", "onumuzdeki hafta", "gelecek haftaya", "onumuzdeki haftaya"]),
           !RelativeDayParser.namesWeekday(text) {
            return .nextWeek
        }
        if says(["bu hafta", "bu haftaki", "hafta boyunca"]) { return .thisWeek }
        return RelativeDayParser.dayOffset(in: text, now: now, calendar: calendar).map { .day(offset: $0) }
    }

    public func interval(now: Date, calendar: Calendar = .current) -> DateInterval? {
        let today = calendar.startOfDay(for: now)
        let start: Date?, end: Date?
        switch self {
        case let .day(offset):
            start = calendar.date(byAdding: .day, value: offset, to: today)
            end = start.flatMap { calendar.date(byAdding: .day, value: 1, to: $0) }
        case .thisWeek:
            start = today
            end = calendar.date(byAdding: .day, value: 7, to: today)
        case .nextWeek:
            start = calendar.dateInterval(of: .weekOfYear, for: now)?.end
            end = start.flatMap { calendar.date(byAdding: .weekOfYear, value: 1, to: $0) }
        case .thisMonth:
            start = today
            end = calendar.dateInterval(of: .month, for: now)?.end
        }
        guard let start, let end else { return nil }
        return DateInterval(start: start, end: end)
    }
}
