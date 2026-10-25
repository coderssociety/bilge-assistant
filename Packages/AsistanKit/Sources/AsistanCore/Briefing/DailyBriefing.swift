import Foundation

/// "Günün özeti" and the first "günaydın" of the day.
public enum BriefingIntent {
    private static let phrases = [
        "gunun ozeti", "gunu ozetle", "bugun neler var", "sabah ozeti", "gunluk ozet", "bugun beni neler bekliyor",
        "brifing", "bugunun ozeti",
    ]

    private static let englishPhrases = [
        "daily briefing", "morning briefing", "brief me", "summary of my day", "summary of the day", "my day look like",
        "my day like", "todays summary", "plan for today",
    ]

    public static func isRequest(_ text: String, language: AssistantLanguage = .turkish) -> Bool {
        let folded = TurkishText.folded(text)
        return (language == .english ? englishPhrases : phrases).contains { folded.contains($0) }
    }

    /// "Günaydın" with nothing else to ask; "günaydın, saat kaç" is a question.
    public static func isMorningGreeting(
        _ text: String, wakePhrase: String = AppIdentity.defaultWakePhrase, language: AssistantLanguage = .turkish
    ) -> Bool {
        let wake = TurkishText.folded(wakePhrase)
        let words = TurkishText.folded(text).split(separator: " ").map(String.init).filter { $0 != wake }
        return words == (language == .english ? ["good", "morning"] : ["gunaydin"])
    }
}

/// The day at a glance, put into a few spoken sentences. Missing parts (no weather, no mail access)
/// are simply left out.
public struct DailyBriefing: Sendable {
    public struct Event: Sendable {
        public let title: String
        public let start: Date

        public init(title: String, start: Date) {
            self.title = title
            self.start = start
        }
    }

    private static let listedEvents = 3
    private static let listedReminders = 2

    public let now: Date
    public let weather: String?
    /// Today's timed events still ahead, in order; nil when the calendar could not be read, which must not
    /// sound like a free day.
    public let events: [Event]?
    /// Reminders due today or overdue.
    public let reminders: [String]
    /// Nil when it could not be checked.
    public let unreadMail: Int?

    public init(now: Date, weather: String?, events: [Event]?, reminders: [String], unreadMail: Int?) {
        self.now = now
        self.weather = weather
        self.events = events
        self.reminders = reminders
        self.unreadMail = unreadMail
    }

    public func text(calendar: Calendar = .current, language: AssistantLanguage = .turkish) -> String {
        if language == .english { return englishText(calendar: calendar) }
        let locale = Locale(identifier: "tr_TR")
        var format = Date.FormatStyle(date: .omitted, time: .omitted, locale: locale, calendar: calendar, timeZone: calendar.timeZone)
        format = format.day().month(.wide).weekday(.wide)
        let date = now.formatted(format)
        var sentences = [greeting(calendar: calendar), "Bugün \(date)."]
        if let weather { sentences.append(weather) }
        sentences.append(eventsSentence(calendar: calendar))
        if let remindersSentence { sentences.append(remindersSentence) }
        if let unreadMail, unreadMail > 0 { sentences.append("\(unreadMail) okunmamış e-postan var.") }
        return sentences.joined(separator: " ")
    }

    private func greeting(calendar: Calendar) -> String {
        switch calendar.component(.hour, from: now) {
        case 5..<12: "Günaydın."
        case 12..<18: "İyi günler."
        default: "İyi akşamlar."
        }
    }

    private func eventsSentence(calendar: Calendar) -> String {
        guard let events else { return "Takvimini okuyamadım." }
        guard !events.isEmpty else { return "Bugün başka etkinliğin yok." }
        let listed = events.prefix(Self.listedEvents).map { event in
            let time = TurkishGrammar.timeLocative(hour: calendar.component(.hour, from: event.start),
                                                   minute: calendar.component(.minute, from: event.start))
            return "\(time) \(event.title)"
        }
        return "Bugün \(events.count) etkinliğin var: \(Self.list(listed, total: events.count))."
    }

    private var remindersSentence: String? {
        guard !reminders.isEmpty else { return nil }
        if reminders.count == 1 { return "Bugünkü anımsatıcın: \(reminders[0])." }
        return "\(reminders.count) anımsatıcın var: \(Self.list(Array(reminders.prefix(Self.listedReminders)), total: reminders.count))."
    }

    private func englishText(calendar: Calendar) -> String {
        var format = Date.FormatStyle(date: .omitted, time: .omitted, locale: AssistantLanguage.english.locale,
                                      calendar: calendar, timeZone: calendar.timeZone)
        format = format.weekday(.wide).month(.wide).day()
        let greeting = switch calendar.component(.hour, from: now) {
        case 5..<12: "Good morning."
        case 12..<18: "Good afternoon."
        default: "Good evening."
        }
        var sentences = [greeting, "Today is \(now.formatted(format))."]
        if let weather { sentences.append(weather) }
        if let events, events.isEmpty {
            sentences.append("You have nothing else on your calendar today.")
        } else if let events {
            let time = Date.FormatStyle(date: .omitted, time: .shortened, locale: AssistantLanguage.english.locale,
                                        calendar: calendar, timeZone: calendar.timeZone)
            let listed = events.prefix(Self.listedEvents).map { "\($0.title) at \($0.start.formatted(time))" }
            let noun = events.count == 1 ? "event" : "events"
            sentences.append("You have \(events.count) \(noun) today: \(Self.englishList(listed, total: events.count)).")
        } else {
            sentences.append("I couldn't read your calendar.")
        }
        if reminders.count == 1 {
            sentences.append("Today's reminder: \(reminders[0]).")
        } else if reminders.count > 1 {
            let listed = Array(reminders.prefix(Self.listedReminders))
            sentences.append("You have \(reminders.count) reminders: \(Self.englishList(listed, total: reminders.count)).")
        }
        if let unreadMail, unreadMail > 0 {
            sentences.append("You have \(unreadMail) unread \(unreadMail == 1 ? "email" : "emails").")
        }
        return sentences.joined(separator: " ")
    }

    /// "a, b, c and 3 more".
    private static func englishList(_ items: [String], total: Int) -> String {
        let rest = total - items.count
        if rest > 0 { return items.joined(separator: ", ") + " and \(rest) more" }
        guard items.count > 1 else { return items.first ?? "" }
        return items.dropLast().joined(separator: ", ") + " and " + items[items.count - 1]
    }

    /// "a, b, c ve 3 tane daha".
    private static func list(_ items: [String], total: Int) -> String {
        let rest = total - items.count
        return rest > 0 ? items.joined(separator: ", ") + " ve \(rest) tane daha" : items.joined(separator: ", ")
    }
}
