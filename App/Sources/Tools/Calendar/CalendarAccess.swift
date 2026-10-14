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

    /// Incomplete reminders due by `date`, overdue ones included, earliest first.
    func dueReminderTitles(until date: Date) async throws -> [String] {
        try await requireReminders()
        let predicate = store.predicateForIncompleteReminders(withDueDateStarting: nil, ending: date, calendars: nil)
        return await withCheckedContinuation { continuation in
            store.fetchReminders(matching: predicate) { reminders in
                let dated = (reminders ?? []).compactMap { reminder -> (Date, String)? in
                    guard let title = reminder.title, let due = reminder.dueDateComponents.flatMap(Calendar.current.date(from:)) else { return nil }
                    return (due, title)
                }
                continuation.resume(returning: dated.sorted { $0.0 < $1.0 }.map(\.1))
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

    /// Timed events in `window` and incomplete reminders due in `dueWindow`. Never asks for access:
    /// a background check must not pop up a permission prompt, so it reads only what is already allowed.
    func alertCandidates(eventsIn window: DateInterval, remindersDueIn dueWindow: DateInterval) async -> [AlertCandidate] {
        var candidates: [AlertCandidate] = []
        if EKEventStore.authorizationStatus(for: .event) == .fullAccess {
            let predicate = store.predicateForEvents(withStart: window.start, end: window.end, calendars: nil)
            candidates += store.events(matching: predicate)
                .filter { !$0.isAllDay && window.contains($0.startDate) && $0.status != .canceled }
                .filter { event in event.attendees?.first(where: \.isCurrentUser)?.participantStatus != .declined }
                .map { event in
                    AlertCandidate(key: "event:\(event.calendarItemIdentifier):\(event.startDate.timeIntervalSince1970)",
                                   title: event.title ?? "Bir etkinlik", date: event.startDate, kind: .event)
                }
        }
        guard EKEventStore.authorizationStatus(for: .reminder) == .fullAccess else { return candidates }
        let predicate = store.predicateForIncompleteReminders(withDueDateStarting: dueWindow.start, ending: dueWindow.end, calendars: nil)
        let reminders: [AlertCandidate] = await withCheckedContinuation { continuation in
            store.fetchReminders(matching: predicate) { reminders in
                continuation.resume(returning: (reminders ?? []).compactMap { reminder in
                    // A reminder due on a day but at no particular time has nothing to announce.
                    guard let components = reminder.dueDateComponents, components.hour != nil,
                          let due = Calendar.current.date(from: components), let title = reminder.title
                    else { return nil }
                    return AlertCandidate(key: "reminder:\(reminder.calendarItemIdentifier):\(due.timeIntervalSince1970)",
                                          title: title, date: due, kind: .reminder)
                })
            }
        }
        return candidates + reminders
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
