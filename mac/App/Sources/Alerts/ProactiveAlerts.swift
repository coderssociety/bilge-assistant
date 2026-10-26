import AsistanCore
import Foundation

/// Speaks calendar events shortly before they start and reminders when they come due, without being
/// asked. It checks once a minute, only while the assistant is listening and the user has turned it on.
@MainActor
final class ProactiveAlerts {
    private static let checkInterval: Duration = .seconds(60)
    /// A reminder that came due while the Mac slept or the assistant was busy is still worth saying.
    private static let reminderGrace: TimeInterval = 5 * 60
    /// Keys are kept a day so an event is not announced again later the same day.
    private static let announcedLifetime: TimeInterval = 24 * 60 * 60

    private let settings: AssistantSettings
    private let isListening: @MainActor () -> Bool
    private let announce: @MainActor (String) async -> Void
    private var announced: [String: Date] = [:]
    private var task: Task<Void, Never>?

    init(settings: AssistantSettings, isListening: @escaping @MainActor () -> Bool,
         announce: @escaping @MainActor (String) async -> Void) {
        self.settings = settings
        self.isListening = isListening
        self.announce = announce
    }

    func start() {
        guard task == nil else { return }
        task = Task { [weak self] in
            while !Task.isCancelled {
                await self?.check()
                try? await Task.sleep(for: Self.checkInterval)
            }
        }
    }

    func stop() {
        task?.cancel()
        task = nil
    }

    private func check(now: Date = .now) async {
        guard settings.proactiveAlertsEnabled, isListening() else { return }
        let lead = TimeInterval(max(settings.eventAlertLeadMinutes, 1) * 60)
        let candidates = await CalendarAccess.shared.alertCandidates(
            eventsIn: DateInterval(start: now.addingTimeInterval(-60), end: now.addingTimeInterval(lead)),
            remindersDueIn: DateInterval(start: now.addingTimeInterval(-Self.reminderGrace), end: now.addingTimeInterval(60)))
        announced = announced.filter { now.timeIntervalSince($0.value) < Self.announcedLifetime }
        let due = UpcomingAlerts.due(candidates, now: now, lead: lead, grace: Self.reminderGrace, announced: Set(announced.keys))
        guard !due.isEmpty else { return }
        due.forEach { announced[$0.key] = now }
        Log.brain.info("Announcing \(due.count) calendar alert(s)")
        Earcon.wake.play()
        await announce(UpcomingAlerts.message(for: due, now: now, language: AppLanguage.current))
    }
}
