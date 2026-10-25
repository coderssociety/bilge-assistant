import Foundation

/// Reads which day a Turkish request refers to ("yarın", "cuma", "haftaya çarşamba", "3 gün sonra", "15 Kasım'da")
/// as an offset from today. A bare weekday means its next occurrence; today's weekday means next week.
public enum RelativeDayParser {
    /// "yarın" comes before the weekdays: in "yarın pazara gitmeyi hatırlat" the market is not Sunday.
    private static let leadingPhrases: [(phrase: String, offset: Int)] = [
        ("yarindan sonra", 2), ("obur gun", 2), ("ertesi gun", 1), ("yarin", 1),
    ]
    private static let nextWeekPhrases = ["haftaya", "gelecek hafta", "onumuzdeki hafta"]
    /// Calendar weekday numbers (1 = Sunday).
    private static let weekdays: [String: Int] = [
        "pazar": 1, "pazartesi": 2, "sali": 3, "carsamba": 4, "persembe": 5, "cuma": 6, "cumartesi": 7,
    ]
    /// Endings a weekday name takes here: "cumaya", "salıki", "cumaları". "pazara", "pazarda" and "pazarı"
    /// are left out on purpose, as they are almost always the market.
    private static let weekdayEndings: Set<String> = ["", "ya", "ye", "yi", "ki", "leri", "lari"]
    private static let months = [
        "ocak", "subat", "mart", "nisan", "mayis", "haziran", "temmuz", "agustos", "eylul", "ekim", "kasim", "aralik",
    ]
    private static let daysLater = try! NSRegularExpression(pattern: #"(\d+) gun sonra"#)
    private static let weeksLater = try! NSRegularExpression(pattern: #"(\d+) hafta sonra"#)
    private static let dayOfMonth = try! NSRegularExpression(
        pattern: #"(?<!\d)(\d{1,2}) (\#(months.joined(separator: "|")))"#)
    private static let dayOfThisMonth = try! NSRegularExpression(pattern: #"(?<!\p{L})ayin (\d{1,2})"#)

    public static func dayOffset(in text: String, now: Date, calendar: Calendar = .current) -> Int? {
        let folded = TurkishText.folded(text)
        if let days = number(daysLater, in: folded) { return days }
        if let weeks = number(weeksLater, in: folded) { return weeks * 7 }
        if let offset = leadingPhrases.first(where: { startsWord(folded, $0.phrase) })?.offset { return offset }
        let words = folded.split(separator: " ").map(String.init)
        if let offset = weekdayOffset(words, now: now, calendar: calendar) { return offset }
        if let offset = dateOffset(folded, now: now, calendar: calendar) { return offset }
        if nextWeekPhrases.contains(where: { startsWord(folded, $0) }) { return 7 }
        return startsWord(folded, "bugun") ? 0 : nil
    }

    /// True when the text names a day of the week, so "haftaya" alone can be read as the whole week.
    public static func namesWeekday(_ text: String) -> Bool {
        TurkishText.folded(text).split(separator: " ").contains { weekday(String($0)) != nil }
    }

    private static func weekdayOffset(_ words: [String], now: Date, calendar: Calendar) -> Int? {
        guard let index = words.firstIndex(where: { weekday($0) != nil }), let target = weekday(words[index]) else { return nil }
        let preceding = words[..<index].suffix(2).joined(separator: " ")
        if nextWeekPhrases.contains(where: { preceding.hasSuffix($0) }) {
            return nextWeekOffset(weekday: target, now: now, calendar: calendar)
        }
        let today = calendar.component(.weekday, from: now)
        let offset = (target - today + 7) % 7
        return offset == 0 ? 7 : offset
    }

    private static func weekday(_ word: String) -> Int? {
        weekdays.first { name, _ in
            word.hasPrefix(name) && weekdayEndings.contains(String(word.dropFirst(name.count)))
        }?.value
    }

    /// "Haftaya salı" is the Tuesday of next calendar week.
    private static func nextWeekOffset(weekday target: Int, now: Date, calendar: Calendar) -> Int? {
        guard let thisWeek = calendar.dateInterval(of: .weekOfYear, for: now) else { return nil }
        let intoWeek = (target - calendar.firstWeekday + 7) % 7
        guard let day = calendar.date(byAdding: .day, value: intoWeek, to: thisWeek.end) else { return nil }
        return days(from: now, to: day, calendar: calendar)
    }

    /// "15 Kasım" is the next 15 November; "ayın 20'si" is the next 20th.
    private static func dateOffset(_ folded: String, now: Date, calendar: Calendar) -> Int? {
        let today = calendar.dateComponents([.year, .month, .day], from: now)
        guard let year = today.year, let month = today.month, let currentDay = today.day else { return nil }
        if let match = firstMatch(dayOfMonth, in: folded), let day = Int(match[0]),
           let monthIndex = months.firstIndex(of: match[1]) {
            let target = monthIndex + 1
            let passed = target < month || (target == month && day < currentDay)
            return offset(year: passed ? year + 1 : year, month: target, day: day, now: now, calendar: calendar)
        }
        if let day = number(dayOfThisMonth, in: folded) {
            let (targetYear, target) = day >= currentDay ? (year, month) : month == 12 ? (year + 1, 1) : (year, month + 1)
            return offset(year: targetYear, month: target, day: day, now: now, calendar: calendar)
        }
        return nil
    }

    private static func offset(year: Int, month: Int, day: Int, now: Date, calendar: Calendar) -> Int? {
        let components = DateComponents(year: year, month: month, day: day)
        guard components.isValidDate(in: calendar), let date = calendar.date(from: components) else { return nil }
        return days(from: now, to: date, calendar: calendar)
    }

    private static func days(from now: Date, to date: Date, calendar: Calendar) -> Int? {
        calendar.dateComponents([.day], from: calendar.startOfDay(for: now), to: calendar.startOfDay(for: date)).day
    }

    private static func startsWord(_ folded: String, _ phrase: String) -> Bool {
        (" " + folded).contains(" " + phrase)
    }

    private static func number(_ pattern: NSRegularExpression, in text: String) -> Int? {
        firstMatch(pattern, in: text).flatMap { Int($0[0]) }
    }

    private static func firstMatch(_ pattern: NSRegularExpression, in text: String) -> [String]? {
        let source = text as NSString
        guard let match = pattern.firstMatch(in: text, range: NSRange(location: 0, length: source.length)) else { return nil }
        return (1..<match.numberOfRanges).map { source.substring(with: match.range(at: $0)) }
    }
}
