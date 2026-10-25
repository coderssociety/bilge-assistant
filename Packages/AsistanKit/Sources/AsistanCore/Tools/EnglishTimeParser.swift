import Foundation

/// English counterparts of `RelativeDayParser` and `TimerPhraseParser`: "tomorrow", "next Friday",
/// "in 3 days"; "10:30", "7 pm", "at ten", "noon"; "in 10 minutes", "half an hour".
public enum EnglishTimeParser {
    private static let units: [String: Int] = [
        "one": 1, "two": 2, "three": 3, "four": 4, "five": 5, "six": 6, "seven": 7, "eight": 8, "nine": 9, "a": 1, "an": 1,
    ]
    private static let teens: [String: Int] = [
        "ten": 10, "eleven": 11, "twelve": 12, "thirteen": 13, "fourteen": 14, "fifteen": 15, "sixteen": 16,
        "seventeen": 17, "eighteen": 18, "nineteen": 19,
    ]
    private static let tens: [String: Int] = [
        "twenty": 20, "thirty": 30, "forty": 40, "fifty": 50, "sixty": 60, "seventy": 70, "eighty": 80, "ninety": 90,
    ]
    /// Calendar weekday numbers (1 = Sunday).
    private static let weekdays: [String: Int] = [
        "sunday": 1, "monday": 2, "tuesday": 3, "wednesday": 4, "thursday": 5, "friday": 6, "saturday": 7,
    ]
    private static let earliestNightHour = 6
    public static let partOfDayWords: Set<String> = ["morning", "afternoon", "evening", "night", "tonight", "noon", "midnight"]

    public static func dayOffset(in text: String, now: Date, calendar: Calendar = .current) -> Int? {
        let words = words(text)
        if let index = words.firstIndex(of: "in"), index + 2 < words.count, ["day", "days"].contains(words[index + 2]),
           let count = number(words[index + 1]) {
            return count
        }
        for (index, word) in words.enumerated() {
            guard let target = weekdays[word] else { continue }
            let today = calendar.component(.weekday, from: now)
            var offset = (target - today + 7) % 7
            if offset == 0 { offset = 7 }
            let nextWeek = index > 0 && words[index - 1] == "next" && offset < 7
            return nextWeek ? offset + 7 : offset
        }
        if contains(words, ["day", "after", "tomorrow"]) { return 2 }
        if words.contains("tomorrow") { return 1 }
        if words.contains("today") || words.contains("tonight") { return 0 }
        return nil
    }

    /// A clock time or a duration, like `TimerPhraseParser.Result`. For appointments a bare "at 3" means
    /// 15:00; for alarms ("wake me up at 6") the hour is taken as said.
    public static func parse(_ text: String, appointment: Bool = true) -> TimerPhraseParser.Result? {
        if let clock = clockTime(text, appointment: appointment) { return TimerPhraseParser.Result(hour: clock.hour, minute: clock.minute, durationSeconds: nil) }
        let seconds = duration(words(text))
        return seconds > 0 ? TimerPhraseParser.Result(hour: nil, minute: nil, durationSeconds: seconds) : nil
    }

    private static func clockTime(_ text: String, appointment: Bool) -> (hour: Int, minute: Int)? {
        let lowered = text.lowercased()
        if let match = lowered.firstMatch(of: /\b(\d{1,2}):(\d{2})\s*(?:([ap])\.?\s*m\b)?/),
           let hour = Int(match.1), let minute = Int(match.2), hour < 24, minute < 60 {
            return (adjusted(hour, meridiem: match.3.map(String.init)), minute)
        }
        if let match = lowered.firstMatch(of: /(?:^|[^\d:])(\d{1,2})\s*([ap])\.?\s*m\b/), let hour = Int(match.1), (1...12).contains(hour) {
            return (adjusted(hour, meridiem: String(match.2)), 0)
        }
        let words = words(text)
        if words.contains("noon") || words.contains("midday") { return (12, 0) }
        if words.contains("midnight") { return (0, 0) }
        // "at ten", "at 7": afternoon for 1-6, as appointments rarely start before 7 in the morning.
        // Only a real number counts: "at a meeting" is not one o'clock.
        let bareHour = words.indices.lazy.compactMap { index -> (Int, Int)? in
            guard words[index] == "at", index + 1 < words.count, !["a", "an"].contains(words[index + 1]),
                  let hour = number(words[index + 1]), (1...12).contains(hour),
                  !(index + 2 < words.count && ["minute", "minutes", "percent"].contains(words[index + 2])) else { return nil }
            return (index, hour)
        }.first
        if let (_, hour) = bareHour {
            // "every night at 12" is midnight and "at 1 at night" the small hours; 6 to 11 are the evening.
            if words.contains("night") || words.contains("nights") {
                return (hour == 12 ? 0 : hour < earliestNightHour ? hour : hour + 12, 0)
            }
            let evening = words.contains("evening") || words.contains("tonight")
            let afternoon = (appointment && hour < 7) || (evening && hour < 12)
            return (afternoon ? hour + 12 : hour, 0)
        }
        return nil
    }

    private static func adjusted(_ hour: Int, meridiem: String?) -> Int {
        switch meridiem {
        case "p": hour < 12 ? hour + 12 : hour
        case "a": hour == 12 ? 0 : hour
        default: hour
        }
    }

    private static func duration(_ words: [String]) -> Int {
        var total = 0
        for (index, word) in words.enumerated() {
            let unit = switch word {
            case "hour", "hours": 3600
            case "minute", "minutes", "min", "mins": 60
            case "second", "seconds", "sec", "secs": 1
            default: 0
            }
            guard unit > 0, index > 0 else { continue }
            if words[index - 1] == "an", index > 1, words[index - 2] == "half" {
                total += unit / 2
            } else if let count = number(endingAt: index - 1, in: words) {
                total += count * unit
            }
            // "an hour and a half"
            if index + 3 < words.count, Array(words[(index + 1)...(index + 3)]) == ["and", "a", "half"] { total += unit / 2 }
        }
        if !contains(words, ["half", "an", "hour"]), contains(words, ["half", "hour"]) { total += 1800 }
        return total
    }

    /// "25", "twenty five", "ninety", "an" ending at `index`.
    private static func number(endingAt index: Int, in words: [String]) -> Int? {
        let word = words[index]
        if let value = Int(word) ?? teens[word] ?? tens[word] { return value }
        guard let unit = units[word] else { return nil }
        if index > 0, let ten = tens[words[index - 1]] { return ten + unit }
        return unit
    }

    private static func number(_ word: String) -> Int? {
        Int(word) ?? units[word] ?? teens[word] ?? tens[word]
    }

    private static func words(_ text: String) -> [String] {
        text.lowercased().split(whereSeparator: { !$0.isLetter && !$0.isNumber }).map(String.init)
    }

    private static func contains(_ words: [String], _ phrase: [String]) -> Bool {
        guard words.count >= phrase.count else { return false }
        return (0...(words.count - phrase.count)).contains { Array(words[$0..<$0 + phrase.count]) == phrase }
    }
}
