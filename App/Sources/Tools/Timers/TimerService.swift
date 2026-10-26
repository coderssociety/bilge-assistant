import AsistanCore
import Foundation
import Observation

/// In-app timers and alarms. They fire while the app is running; with a file they are also kept across restarts, and
/// the ones whose time passed while the app was closed are announced once at the next start.
@MainActor
@Observable
final class TimerService {
    struct ScheduledTimer: Identifiable, Sendable, Codable {
        var id = UUID()
        let fireDate: Date
        let label: String?
    }

    private(set) var timers: [ScheduledTimer] = []
    private var tasks: [UUID: Task<Void, Never>] = [:]
    private let announce: @MainActor (String) async -> Void
    /// Only the app passes one: benchmarks keep timers in memory and post no notifications.
    private let fileURL: URL?

    init(fileURL: URL? = nil, announce: @escaping @MainActor (String) async -> Void) {
        self.fileURL = fileURL
        self.announce = announce
        let saved = Self.load(from: fileURL)
        let now = Date.now
        for timer in saved.filter({ $0.fireDate > now }) { start(timer) }
        let missed = saved.filter { $0.fireDate <= now }.sorted { $0.fireDate < $1.fireDate }
        guard !missed.isEmpty else { return }
        save()
        Log.app.info("\(missed.count) timers went off while the app was closed")
        let message = Self.missedMessage(missed)
        Task { [weak self] in await self?.notifyAndAnnounce(message, id: "missed-timers") }
    }

    static func defaultFileURL() -> URL? {
        do {
            return try ModelStorage.root().appending(path: "timers.json")
        } catch {
            Log.app.error("No storage for timers: \(error.localizedDescription, privacy: .public)")
            return nil
        }
    }

    func schedule(at fireDate: Date, label: String?) -> ScheduledTimer {
        let timer = ScheduledTimer(fireDate: fireDate, label: label)
        start(timer)
        save()
        if fileURL != nil { Task { await AlertNotifications.requestPermission() } }
        return timer
    }

    func cancel(_ id: UUID) -> Bool {
        guard let task = tasks.removeValue(forKey: id) else { return false }
        task.cancel()
        timers.removeAll { $0.id == id }
        save()
        return true
    }

    func cancelAll() -> Int {
        let count = timers.count
        tasks.values.forEach { $0.cancel() }
        tasks.removeAll()
        timers.removeAll()
        save()
        return count
    }

    private func start(_ timer: ScheduledTimer) {
        timers.append(timer)
        timers.sort { $0.fireDate < $1.fireDate }
        tasks[timer.id] = Task { [weak self] in
            try? await Task.sleep(for: .seconds(max(0, timer.fireDate.timeIntervalSinceNow)))
            guard !Task.isCancelled else { return }
            await self?.fire(timer)
        }
    }

    private func fire(_ timer: ScheduledTimer) async {
        timers.removeAll { $0.id == timer.id }
        tasks[timer.id] = nil
        save()
        Earcon.wake.play()
        let message = timer.label.map { String(localized: "Hatırlatma: \($0).") }
            ?? String(localized: "Zamanlayıcı doldu.")
        await notifyAndAnnounce(message, id: timer.id.uuidString)
    }

    /// The notification stays in Notification Center for when nobody heard it.
    private func notifyAndAnnounce(_ message: String, id: String) async {
        if fileURL != nil { await AlertNotifications.post(id: id, title: AppIdentity.name, body: message) }
        await announce(message)
    }

    private static func missedMessage(_ missed: [ScheduledTimer]) -> String {
        let listed = missed.map { timer in
            [timer.fireDate.formatted(date: .omitted, time: .shortened), timer.label].compactMap(\.self).joined(separator: " ")
        }
        return String(localized: "\(AppIdentity.name) kapalıyken şu zamanlayıcıların zamanı geçti: \(listed.joined(separator: ", ")).")
    }

    /// A timer that cannot be saved still goes off; only a restart would lose it.
    private func save() {
        guard let fileURL else { return }
        do {
            try PrivateFile.write(try JSONEncoder().encode(timers), to: fileURL)
        } catch {
            Log.app.error("Could not save timers: \(error.localizedDescription, privacy: .public)")
        }
    }

    private static func load(from url: URL?) -> [ScheduledTimer] {
        guard let url, FileManager.default.fileExists(atPath: url.path) else { return [] }
        do {
            return try JSONDecoder().decode([ScheduledTimer].self, from: Data(contentsOf: url))
        } catch {
            Log.app.error("Saved timers unreadable: \(error.localizedDescription, privacy: .public)")
            return []
        }
    }
}
