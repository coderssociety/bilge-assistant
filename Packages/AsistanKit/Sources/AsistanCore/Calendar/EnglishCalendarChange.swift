import Foundation

/// Reads an English cancel or move request: "cancel tomorrow's meeting", "move the dentist appointment to
/// Friday", "move the 3 o'clock meeting to 4", "push the standup back half an hour".
enum EnglishCalendarChange {
    private static let cancelVerbs: Set<String> = ["cancel", "delete", "remove", "clear", "drop"]
    private static let moveVerbs: Set<String> = ["move", "reschedule", "push", "postpone", "shift", "bring", "change", "delay"]
    private static let leadingFillers: Set<String> = ["please", "can", "could", "would", "you", "will"]
    private static let allWords: Set<String> = ["all", "every", "series", "whole", "occurrences", "recurring"]
    private static let kindWords: Set<String> = ["meeting", "meetings", "appointment", "appointments", "event", "events",
                                                 "session", "interview"]
    private static let notEvents: Set<String> = [
        "alarm", "alarms", "timer", "timers", "reminder", "reminders", "note", "notes", "file", "files", "email", "emails",
        "mail", "message", "messages", "song", "order", "subscription", "tab", "window", "download", "todo",
    ]
    private static let stopWords: Set<String> = [
        "the", "my", "a", "an", "at", "on", "of", "for", "in", "this", "that", "next", "o", "clock", "oclock", "pm", "am",
        "today", "tomorrow", "tonight", "morning", "afternoon", "evening", "noon", "week", "day", "after", "it", "please",
        "monday", "tuesday", "wednesday", "thursday", "friday", "saturday", "sunday", "from", "calendar", "s", "one", "them",
        "hour", "hours", "minute", "minutes", "half",
    ]
    private static let shiftMarkers: Set<String> = ["by", "back", "forward", "earlier", "later", "ahead"]
    private static let targetMarkers: Set<String> = ["to", "until", "till", "for"]

    static func parse(_ command: String, now: Date, calendar: Calendar) -> CalendarChange? {
        let words = normalizedWords(command)
        guard let verbIndex = words.firstIndex(where: { !leadingFillers.contains($0) }) else { return nil }
        let verb = words[verbIndex]
        let isMove = moveVerbs.contains(verb)
        guard isMove || cancelVerbs.contains(verb) else { return nil }
        var rest = Array(words[(verbIndex + 1)...])
        guard !rest.contains(where: notEvents.contains) else { return nil }
        let allOccurrences = rest.contains(where: allWords.contains)
        rest.removeAll { allWords.contains($0) }
        var eventWords = rest
        var targetWords: [String] = []
        if isMove, let split = rest.firstIndex(where: { targetMarkers.contains($0) || shiftMarkers.contains($0) }) {
            eventWords = Array(rest[..<split])
            targetWords = Array(rest[split...])
        }
        guard !eventWords.isEmpty else { return nil }
        let event = describeEvent(eventWords, now: now, calendar: calendar)
        guard isMove else { return CalendarChange(action: .cancel, event: event, allOccurrences: allOccurrences) }
        var target = describeTarget(targetWords, now: now, calendar: calendar)
        // "Move the meeting an hour later": the duration sits before the marker.
        if target.isEmpty, case let whole = describeTarget(rest, now: now, calendar: calendar), whole.shiftMinutes != nil {
            target = whole
        }
        if target.isEmpty, verb != "postpone", verb != "reschedule" { return nil }
        return CalendarChange(action: .move(target), event: event, allOccurrences: allOccurrences)
    }

    /// "Tomorrow's" and "Friday's" read as the day; "3:00" stays one word.
    private static func normalizedWords(_ command: String) -> [String] {
        command.lowercased().replacingOccurrences(of: "'s", with: "").replacingOccurrences(of: "’s", with: "")
            .split { $0.isWhitespace || ($0.isPunctuation && $0 != ":") }
            .map(String.init)
    }

    private static func describeEvent(_ words: [String], now: Date, calendar: Calendar) -> CalendarChange.Event {
        let text = words.joined(separator: " ")
        let clock = EnglishTimeParser.parse(spokenHours(words).joined(separator: " "), appointment: true)
        var event = CalendarChange.Event(period: CalendarPeriod.parse(text, language: .english, now: now, calendar: calendar),
                                         hour: clock?.hour, minute: clock?.hour == nil ? nil : clock?.minute)
        for word in words where !stopWords.contains(word) && word.first?.isNumber != true {
            if kindWords.contains(word) { event.kindWords.append(word) } else { event.titleWords.append(word) }
        }
        return event
    }

    private static func describeTarget(_ words: [String], now: Date, calendar: Calendar) -> CalendarChange.Target {
        let text = words.joined(separator: " ")
        var target = CalendarChange.Target()
        let parsed = EnglishTimeParser.parse(spokenHours(words).joined(separator: " "), appointment: true)
        if let seconds = parsed?.durationSeconds {
            let earlier = words.contains("earlier") || words.contains("forward")
            target.shiftMinutes = (earlier ? -1 : 1) * seconds / 60
            return target
        }
        if words.contains("week"), words.contains("next") || words.contains("a"), !words.contains(where: isWeekday) {
            target.shiftDays = 7
        } else {
            target.dayOffset = EnglishTimeParser.dayOffset(in: text, now: now, calendar: calendar)
        }
        if let hour = parsed?.hour { (target.hour, target.minute) = (hour, parsed?.minute ?? 0) }
        return target
    }

    private static let units: Set<String> = ["minute", "minutes", "hour", "hours", "day", "days", "week", "weeks"]

    /// The time parser reads a bare hour only after "at": "the 3 o'clock meeting" and "to 4" become "at 3", "at 4".
    private static func spokenHours(_ words: [String]) -> [String] {
        var result: [String] = []
        var index = 0
        while index < words.count {
            let word = words[index]
            let next = index + 1 < words.count ? words[index + 1] : ""
            let isHour = EnglishTimeParser.parse("at \(next)")?.hour != nil
                && !(index + 2 < words.count && units.contains(words[index + 2]))
            if word == "to" || word == "until" || word == "till", isHour {
                result.append("at")
            } else if word == "o", next == "clock", let last = result.last, EnglishTimeParser.parse("at \(last)")?.hour != nil {
                result.insert("at", at: result.count - 1)
                index += 2
                continue
            } else {
                result.append(word)
            }
            index += 1
        }
        return result
    }

    private static func isWeekday(_ word: String) -> Bool {
        ["monday", "tuesday", "wednesday", "thursday", "friday", "saturday", "sunday"].contains(word)
    }
}
