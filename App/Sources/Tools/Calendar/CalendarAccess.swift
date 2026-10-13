import AsistanCore
@preconcurrency import EventKit

enum CalendarAccessError: LocalizedError {
    case denied(String)

    var errorDescription: String? {
        switch self {
        case let .denied(what): "\(what) erişim izni yok. Sistem Ayarları > Gizlilik ve Güvenlik bölümünden izin verilmeli."
        }
    }
}

struct CalendarEventSummary: Sendable {
    let title: String
    let start: Date
    let isAllDay: Bool
}

/// One shared EKEventStore; EventKit expects a long-lived store per app.
/// EventKit objects are not Sendable, so only value summaries leave this actor.
actor CalendarAccess {
    static let shared = CalendarAccess()
    private let store = EKEventStore()

    func events(from start: Date, to end: Date) async throws -> [CalendarEventSummary] {
        try await requireEvents()
        let predicate = store.predicateForEvents(withStart: start, end: end, calendars: nil)
        return store.events(matching: predicate)
            .sorted { $0.startDate < $1.startDate }
            .map { CalendarEventSummary(title: $0.title ?? "Başlıksız", start: $0.startDate, isAllDay: $0.isAllDay) }
    }

    func incompleteReminderTitles() async throws -> [String] {
        try await requireReminders()
        let predicate = store.predicateForIncompleteReminders(withDueDateStarting: nil, ending: nil, calendars: nil)
        return await withCheckedContinuation { continuation in
            store.fetchReminders(matching: predicate) { reminders in
                continuation.resume(returning: (reminders ?? []).compactMap(\.title))
            }
        }
    }

    /// Marks the incomplete reminder best matching `query` as done; returns its title, or nil if none matched.
    func completeReminder(matching query: String) async throws -> String? {
        try await requireReminders()
        let predicate = store.predicateForIncompleteReminders(withDueDateStarting: nil, ending: nil, calendars: nil)
        // EKReminder is not Sendable; only identifiers and titles cross the callback.
        let candidates: [(id: String, title: String)] = await withCheckedContinuation { continuation in
            store.fetchReminders(matching: predicate) { reminders in
                continuation.resume(returning: (reminders ?? []).compactMap { reminder in
                    reminder.title.map { (reminder.calendarItemIdentifier, $0) }
                })
            }
        }
        guard let title = PhraseMatcher.bestMatch(for: query, in: candidates.map(\.title)),
              let id = candidates.first(where: { $0.title == title })?.id,
              let reminder = store.calendarItem(withIdentifier: id) as? EKReminder
        else { return nil }
        reminder.isCompleted = true
        try store.save(reminder, commit: true)
        return title
    }

    func addEvent(title: String, start: Date, end: Date) async throws {
        try await requireEvents()
        let event = EKEvent(eventStore: store)
        event.title = title
        event.startDate = start
        event.endDate = end
        event.calendar = store.defaultCalendarForNewEvents
        try store.save(event, span: .thisEvent, commit: true)
    }

    func addReminder(title: String, due: Date?) async throws {
        try await requireReminders()
        let reminder = EKReminder(eventStore: store)
        reminder.title = title
        reminder.calendar = store.defaultCalendarForNewReminders()
        if let due {
            reminder.dueDateComponents = Calendar.current.dateComponents([.year, .month, .day, .hour, .minute], from: due)
            reminder.addAlarm(EKAlarm(absoluteDate: due))
        }
        try store.save(reminder, commit: true)
    }

    private func requireEvents() async throws {
        switch EKEventStore.authorizationStatus(for: .event) {
        case .fullAccess: return
        case .notDetermined:
            guard try await store.requestFullAccessToEvents() else { throw CalendarAccessError.denied("Takvime") }
        default:
            throw CalendarAccessError.denied("Takvime")
        }
    }

    private func requireReminders() async throws {
        switch EKEventStore.authorizationStatus(for: .reminder) {
        case .fullAccess: return
        case .notDetermined:
            guard try await store.requestFullAccessToReminders() else { throw CalendarAccessError.denied("Anımsatıcılara") }
        default:
            throw CalendarAccessError.denied("Anımsatıcılara")
        }
    }
}
