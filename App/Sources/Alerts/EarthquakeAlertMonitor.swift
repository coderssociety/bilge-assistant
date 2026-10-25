import AsistanCore
import Foundation
import UserNotifications

/// Speaks and shows strong earthquakes near the user's city while the app runs, if the user wants that.
/// AFAD (or Kandilli) is asked every two minutes for recent events of magnitude 4 and up only, which is
/// usually an empty list; after failures it waits longer, up to ten minutes.
@MainActor
final class EarthquakeAlertMonitor {
    private static let pollInterval: Duration = .seconds(120)
    private static let longestWait: Duration = .seconds(600)
    /// A little more than the alert age limit, so an event published late is still seen.
    private static let lookBack: TimeInterval = EarthquakeAlertLog.maximumAge + 5 * 60

    private let settings: AssistantSettings
    private let announce: @MainActor (String) async -> Void
    private var log = EarthquakeAlertLog()
    private var failures = 0
    private var askedForNotifications = false
    private var task: Task<Void, Never>?

    init(settings: AssistantSettings, announce: @escaping @MainActor (String) async -> Void) {
        self.settings = settings
        self.announce = announce
    }

    func start() {
        guard task == nil else { return }
        task = Task { [weak self] in
            while !Task.isCancelled {
                guard let wait = await self?.check() else { return }
                try? await Task.sleep(for: wait)
            }
        }
    }

    func stop() {
        task?.cancel()
        task = nil
    }

    private func check() async -> Duration {
        guard settings.nearbyEarthquakeAlertsEnabled else {
            failures = 0
            return Self.pollInterval
        }
        if !askedForNotifications {
            askedForNotifications = true
            await AlertNotifications.requestPermission()
        }
        let now = Date.now
        do {
            guard let home = try await CityLocator.shared.place(for: CityLocator.userCity) else {
                Log.app.error("Earthquake alerts: the weather city was not found")
                return Self.pollInterval
            }
            let result = try await EarthquakeFeed.fetch(since: now.addingTimeInterval(-Self.lookBack),
                                                        minimumMagnitude: EarthquakeAlertLog.minimumMagnitude, now: now)
            failures = 0
            for quake in log.newAlerts(in: result.earthquakes, home: home.centre, now: now) {
                await alert(quake, home: home, now: now)
            }
            return Self.pollInterval
        } catch is CancellationError {
            return Self.pollInterval
        } catch {
            failures += 1
            let wait = min(Self.pollInterval * (1 << min(failures, 3)), Self.longestWait)
            Log.app.error("Earthquake check failed (\(self.failures)): \(error.localizedDescription, privacy: .public)")
            return wait
        }
    }

    private func alert(_ quake: Earthquake, home: EarthquakeReport.Place, now: Date) async {
        let language = AppLanguage.current
        let message = EarthquakeReport.alert(quake, home: home, now: now, language: language)
        Log.app.info("Announcing earthquake \(quake.id, privacy: .public)")
        await AlertNotifications.post(id: quake.id, title: EarthquakeReport.alertTitle(quake, language: language), body: message)
        Earcon.wake.play()
        await announce(message)
    }
}

enum AlertNotifications {
    static func requestPermission() async {
        do {
            _ = try await UNUserNotificationCenter.current().requestAuthorization(options: [.alert])
        } catch {
            Log.app.error("Notification permission failed: \(error.localizedDescription, privacy: .public)")
        }
    }

    static func post(id: String, title: String, body: String) async {
        let content = UNMutableNotificationContent()
        content.title = title
        content.body = body
        do {
            try await UNUserNotificationCenter.current().add(UNNotificationRequest(identifier: id, content: content, trigger: nil))
        } catch {
            Log.app.error("Notification failed: \(error.localizedDescription, privacy: .public)")
        }
    }
}
