import Foundation

/// Cancelling or moving a calendar event: "yarınki toplantıyı iptal et", "diş hekimi randevusunu cumaya al",
/// "saat 3'teki toplantıyı 4'e ertele". The event is described by words of its title and when it is.
public struct CalendarChange: Equatable, Sendable {
    public enum Action: Equatable, Sendable {
        case cancel
        case move(Target)
    }

    /// Where a moved event goes; whatever is not said keeps the event's own day or time.
    public struct Target: Equatable, Sendable {
        public var dayOffset: Int?
        public var hour: Int?
        public var minute: Int?
        /// "Haftaya ertele": days after the event's own date.
        public var shiftDays: Int?
        /// "1 saat ertele", "yarım saat öne al".
        public var shiftMinutes: Int?

        public init(dayOffset: Int? = nil, hour: Int? = nil, minute: Int? = nil, shiftDays: Int? = nil, shiftMinutes: Int? = nil) {
            self.dayOffset = dayOffset
            self.hour = hour
            self.minute = minute
            self.shiftDays = shiftDays
            self.shiftMinutes = shiftMinutes
        }

        public var isEmpty: Bool { self == Target() }
    }

    public struct Event: Equatable, Sendable {
        /// Words of the title as said: "diş hekimi".
        public var titleWords: [String]
        /// "toplantı", "randevu": used only when nothing more specific is said.
        public var kindWords: [String]
        public var period: CalendarPeriod?
        public var hour: Int?
        public var minute: Int?

        public init(titleWords: [String] = [], kindWords: [String] = [], period: CalendarPeriod? = nil,
                    hour: Int? = nil, minute: Int? = nil) {
            self.titleWords = titleWords
            self.kindWords = kindWords
            self.period = period
            self.hour = hour
            self.minute = minute
        }
    }

    public var action: Action
    public var event: Event
    /// "Hepsini", "all of them": every following occurrence of a repeating event, not only this one.
    public var allOccurrences: Bool

    public init(action: Action, event: Event, allOccurrences: Bool = false) {
        self.action = action
        self.event = event
        self.allOccurrences = allOccurrences
    }

    public static func parse(_ command: String, language: AssistantLanguage, now: Date = .now,
                             calendar: Calendar = .current) -> CalendarChange? {
        language == .english
            ? EnglishCalendarChange.parse(command, now: now, calendar: calendar)
            : TurkishCalendarChange.parse(command, now: now, calendar: calendar)
    }

    /// An event kind, a day or a time is said, so the request is about the calendar whatever the model chose.
    public var isClearlyAboutCalendar: Bool {
        !event.kindWords.isEmpty || event.period != nil || event.hour != nil
    }

    static let calendarActions: Set<String> = ["addCalendarEvent", "readCalendar", "changeCalendarEvent"]

    /// The action for a request the model routed to `action`: changeCalendarEvent when it cancels or moves an event.
    static func reviewedAction(_ action: String, command: String, language: AssistantLanguage) -> String? {
        guard let change = parse(command, language: language),
              change.isClearlyAboutCalendar || calendarActions.contains(action) else { return nil }
        return "changeCalendarEvent"
    }
}

/// An event as the calendar holds it, reduced to what matching needs.
public struct CalendarEventCandidate: Equatable, Sendable {
    public let id: String
    public let title: String
    public let start: Date
    public let end: Date
    public let isAllDay: Bool
    public let isRecurring: Bool

    public init(id: String, title: String, start: Date, end: Date, isAllDay: Bool, isRecurring: Bool) {
        self.id = id
        self.title = title
        self.start = start
        self.end = end
        self.isAllDay = isAllDay
        self.isRecurring = isRecurring
    }
}

extension CalendarChange {
    /// Without a day, events this far ahead are looked at.
    public static let lookAheadDays = 30

    public func searchInterval(now: Date, calendar: Calendar = .current) -> DateInterval? {
        if let period = event.period { return period.interval(now: now, calendar: calendar) }
        let today = calendar.startOfDay(for: now)
        guard let end = calendar.date(byAdding: .day, value: Self.lookAheadDays, to: today) else { return nil }
        return DateInterval(start: today, end: end)
    }

    /// The events the request can mean. Without a day, only events not yet over count, and occurrences of one
    /// title ("standup toplantısını iptal et") mean the next of them.
    public func matches(in candidates: [CalendarEventCandidate], now: Date, calendar: Calendar = .current) -> [CalendarEventCandidate] {
        guard let interval = searchInterval(now: now, calendar: calendar) else { return [] }
        var pool = candidates.sorted { $0.start < $1.start }
            .filter { interval.start <= $0.start && $0.start < interval.end }
        if event.period == nil { pool = pool.filter { $0.end > now } }
        if let hour = event.hour {
            pool = pool.filter { candidate in
                let time = calendar.dateComponents([.hour, .minute], from: candidate.start)
                return !candidate.isAllDay && time.hour == hour && (event.minute == nil || time.minute == event.minute)
            }
        }
        if !event.titleWords.isEmpty {
            let query = event.titleWords.joined(separator: " ")
            pool = pool.filter { PhraseMatcher.matches(query, title: $0.title) }
        } else if !event.kindWords.isEmpty {
            let query = event.kindWords.joined(separator: " ")
            let ofKind = pool.filter { PhraseMatcher.matches(query, title: $0.title) }
            // "Yarınki randevumu iptal et" for an event titled "Diş hekimi": the day alone points at it.
            if !ofKind.isEmpty || (event.period == nil && event.hour == nil) { pool = ofKind }
        } else if event.period == nil, event.hour == nil {
            return []
        }
        if event.period == nil, let first = pool.first, pool.allSatisfy({ $0.title == first.title }) { return [first] }
        return pool
    }

    /// Where `candidate` goes when moved; nil when the target says nothing usable, or gives an all-day event a time.
    public func newStart(for candidate: CalendarEventCandidate, now: Date, calendar: Calendar = .current) -> Date? {
        guard case let .move(target) = action, !target.isEmpty else { return nil }
        if let minutes = target.shiftMinutes {
            return candidate.isAllDay ? nil : candidate.start.addingTimeInterval(TimeInterval(minutes * 60))
        }
        let ownDay = calendar.startOfDay(for: candidate.start)
        let day: Date?
        if let shift = target.shiftDays {
            day = calendar.date(byAdding: .day, value: shift, to: ownDay)
        } else if let offset = target.dayOffset {
            day = calendar.date(byAdding: .day, value: offset, to: calendar.startOfDay(for: now))
        } else {
            day = ownDay
        }
        guard let day else { return nil }
        if candidate.isAllDay { return target.hour == nil ? day : nil }
        let own = calendar.dateComponents([.hour, .minute], from: candidate.start)
        let hour = target.hour ?? own.hour ?? 0
        let minute = target.hour == nil ? own.minute ?? 0 : target.minute ?? 0
        return calendar.date(bySettingHour: hour, minute: minute, second: 0, of: day)
    }
}
