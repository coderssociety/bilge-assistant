import AsistanCore
import Foundation

/// Hands each routine to `run` when it comes due, while the assistant is listening. A time that passes while the app
/// is closed, listening is off or the Mac sleeps is skipped rather than caught up later.
@MainActor
final class RoutineScheduler {
    private static let longestWait: TimeInterval = 30
    private static let shortestWait: TimeInterval = 0.25
    /// A routine due longer ago than this (the Mac was asleep) is not run late.
    private static let grace: TimeInterval = 10 * 60

    private let store: RoutineStore
    private let isListening: @MainActor () -> Bool
    private let run: @MainActor (Routine) async -> Void
    private var lastCheck = Date.now
    private var task: Task<Void, Never>?

    init(store: RoutineStore, isListening: @escaping @MainActor () -> Bool, run: @escaping @MainActor (Routine) async -> Void) {
        self.store = store
        self.isListening = isListening
        self.run = run
    }

    func start() {
        guard task == nil else { return }
        lastCheck = .now
        task = Task { [weak self] in
            while !Task.isCancelled {
                guard let wait = self?.secondsToNext() else { return }
                try? await Task.sleep(for: .seconds(wait))
                await self?.check()
            }
        }
    }

    func stop() {
        task?.cancel()
        task = nil
    }

    private func check(now: Date = .now) async {
        // A clock set back must not make anything due twice.
        let since = min(lastCheck, now)
        lastCheck = now
        let due = RoutineSchedule.due(store.routines, after: since, upTo: now, grace: Self.grace)
        guard !due.isEmpty else { return }
        guard isListening() else {
            Log.brain.info("Skipped \(due.count) routine(s): not listening")
            return
        }
        for routine in due {
            Log.brain.info("Running the \(routine.hour, privacy: .public):\(routine.minute, privacy: .public) routine")
            await run(routine)
        }
    }

    private func secondsToNext(now: Date = .now) -> TimeInterval {
        guard let next = store.routines.compactMap({ RoutineSchedule.nextOccurrence(of: $0, after: now) }).min() else {
            return Self.longestWait
        }
        return min(Self.longestWait, max(Self.shortestWait, next.timeIntervalSince(now)))
    }
}
