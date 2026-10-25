import Foundation

/// When a calendar event or reminder falls. The day and clock time stated in the (number- and
/// time-resolved) command override the model's values; the model's guesses only fill gaps.
public enum AppointmentTime {
    public struct Moment: Equatable, Sendable {
        public var dayOffset: Int?
        public var hour: Int?
        public var minute: Int?

        public init(dayOffset: Int?, hour: Int?, minute: Int?) {
            self.dayOffset = dayOffset
            self.hour = hour
            self.minute = minute
        }
    }

    private static let turkishPartOfDayWords = ["sabah", "ogle", "aksam", "gece"]

    /// A model hour is kept only when the text names a part of day ("yarın akşam"); otherwise it was
    /// invented, so it is dropped. A model day is kept when the text names none, as the model may have
    /// read it from the previous turn.
    public static func refine(_ model: Moment, command: String, language: AssistantLanguage, now: Date,
                              calendar: Calendar = .current) -> Moment {
        let english = language == .english
        let saidDay = english
            ? EnglishTimeParser.dayOffset(in: command, now: now, calendar: calendar)
            : RelativeDayParser.dayOffset(in: command, now: now, calendar: calendar)
        let parsed = english ? EnglishTimeParser.parse(command) : TimerPhraseParser.parse(command, appointment: true)
        let words = TurkishText.folded(command).split(separator: " ").map(String.init)
        let laterWords: Set<String> = english ? ["in", "later"] : ["sonra"]
        // "2 saat sonra hatırlat"; without "sonra", "2 saatlik toplantı" is how long it lasts.
        if saidDay == nil, let seconds = parsed?.durationSeconds, words.contains(where: laterWords.contains) {
            return moment(after: seconds, now: now, calendar: calendar)
        }
        let day = saidDay ?? model.dayOffset
        var refined = Moment(dayOffset: day, hour: nil, minute: nil)
        if let hour = parsed?.hour {
            (refined.hour, refined.minute) = (hour, parsed?.minute)
        } else if mentionsPartOfDay(words, english: english) {
            (refined.hour, refined.minute) = (model.hour, model.minute)
        }
        // "Saat 9'da" said at 10:00 with no day means tomorrow morning, not an hour ago.
        if saidDay == nil, (day ?? 0) == 0, let hour = refined.hour,
           let today = calendar.date(bySettingHour: hour, minute: refined.minute ?? 0, second: 0, of: now), today <= now {
            refined.dayOffset = 1
        }
        return refined
    }

    private static func mentionsPartOfDay(_ words: [String], english: Bool) -> Bool {
        english
            ? words.contains(where: EnglishTimeParser.partOfDayWords.contains)
            : words.contains { word in turkishPartOfDayWords.contains(where: word.hasPrefix) }
    }

    private static func moment(after seconds: Int, now: Date, calendar: Calendar) -> Moment {
        let due = now.addingTimeInterval(TimeInterval(seconds))
        let day = calendar.dateComponents([.day], from: calendar.startOfDay(for: now), to: calendar.startOfDay(for: due)).day
        let time = calendar.dateComponents([.hour, .minute], from: due)
        return Moment(dayOffset: day, hour: time.hour, minute: time.minute)
    }
}
