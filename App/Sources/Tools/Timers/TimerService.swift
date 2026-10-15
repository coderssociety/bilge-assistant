import Foundation
import Observation

/// In-app timers and alarms. They only fire while the app is running.
@MainActor
@Observable
final class TimerService {
    struct ScheduledTimer: Identifiable, Sendable {
        let id = UUID()
        let fireDate: Date
        let label: String?
    }

    private(set) var timers: [ScheduledTimer] = []
    private var tasks: [UUID: Task<Void, Never>] = [:]
    private let announce: @MainActor (String) async -> Void

    init(announce: @escaping @MainActor (String) async -> Void) {
        self.announce = announce
    }

    func schedule(at fireDate: Date, label: String?) -> ScheduledTimer {
        let timer = ScheduledTimer(fireDate: fireDate, label: label)
        timers.append(timer)
        timers.sort { $0.fireDate < $1.fireDate }
        tasks[timer.id] = Task { [weak self] in
            try? await Task.sleep(for: .seconds(max(0, fireDate.timeIntervalSinceNow)))
            guard !Task.isCancelled else { return }
            await self?.fire(timer)
        }
        return timer
    }

    func cancelAll() -> Int {
        let count = timers.count
        tasks.values.forEach { $0.cancel() }
        tasks.removeAll()
        timers.removeAll()
        return count
    }

    private func fire(_ timer: ScheduledTimer) async {
        timers.removeAll { $0.id == timer.id }
        tasks[timer.id] = nil
        Earcon.wake.play()
        let message = timer.label.map { String(localized: "Hatırlatma: \($0).") }
            ?? String(localized: "Zamanlayıcı doldu.")
        await announce(message)
    }
}
