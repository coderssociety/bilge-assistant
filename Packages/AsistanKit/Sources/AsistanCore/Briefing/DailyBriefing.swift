import Foundation

/// "Günün özeti" and the first "günaydın" of the day.
public enum BriefingIntent {
    private static let phrases = [
        "gunun ozeti", "gunu ozetle", "bugun neler var", "sabah ozeti", "gunluk ozet", "bugun beni neler bekliyor",
        "brifing", "bugunun ozeti",
    ]

    public static func isRequest(_ text: String) -> Bool {
        let folded = TurkishText.folded(text)
        return phrases.contains { folded.contains($0) }
    }

    /// "Günaydın" with nothing else to ask; "günaydın, saat kaç" is a question.
    public static func isMorningGreeting(_ text: String, wakePhrase: String = AppIdentity.defaultWakePhrase) -> Bool {
        let wake = TurkishText.folded(wakePhrase)
        let words = TurkishText.folded(text).split(separator: " ").map(String.init).filter { $0 != wake }
        return words == ["gunaydin"]
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
    /// Today's timed events still ahead, in order.
    public let events: [Event]
    /// Reminders due today or overdue.
    public let reminders: [String]
    /// Nil when it could not be checked.
    public let unreadMail: Int?

    public init(now: Date, weather: String?, events: [Event], reminders: [String], unreadMail: Int?) {
        self.now = now
        self.weather = weather
        self.events = events
        self.reminders = reminders
        self.unreadMail = unreadMail
    }

    public func text(calendar: Calendar = .current) -> String {
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

    /// "a, b, c ve 3 tane daha".
    private static func list(_ items: [String], total: Int) -> String {
        let rest = total - items.count
        return rest > 0 ? items.joined(separator: ", ") + " ve \(rest) tane daha" : items.joined(separator: ", ")
    }
}
