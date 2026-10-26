import AsistanCore
import Foundation
import Observation

/// Asks GitHub about a newer Bilge once a day while the app runs, and remembers what it was told, so a newer
/// release found yesterday is still offered after a restart without asking again.
@MainActor
@Observable
final class UpdateChecker {
    enum Outcome: Equatable {
        case upToDate(String)
        case available(ReleaseCheck.Release)
        case failed(String)
    }

    private enum Key {
        static let lastChecked = "updateLastChecked"
        static let newer = "updateNewerRelease"
        static let announced = "updateAnnouncedVersion"
    }

    private static let firstCheckDelay = Duration.seconds(60)
    private static let pollInterval = Duration.seconds(3600)
    private static let requestTimeout: TimeInterval = 15

    /// A published release newer than this build, once known.
    private(set) var available: ReleaseCheck.Release?
    let installer = UpdateInstaller()
    /// Told about a newer release the first time a daily check finds it, once per version.
    @ObservationIgnored var onNewRelease: ((ReleaseCheck.Release) -> Void)?

    /// Whether `available` can be installed from inside Bilge rather than from its release page.
    var canInstall: Bool {
        available?.macPackage != nil && available?.checksums != nil && UpdateInstaller.canReplaceItself
    }
    @ObservationIgnored private let settings: AssistantSettings
    @ObservationIgnored private let defaults: UserDefaults
    @ObservationIgnored private var loop: Task<Void, Never>?

    let runningVersion = Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? ""

    init(settings: AssistantSettings, defaults: UserDefaults = .standard) {
        self.settings = settings
        self.defaults = defaults
        available = defaults.data(forKey: Key.newer)
            .flatMap { try? JSONDecoder().decode(ReleaseCheck.Release.self, from: $0) }
            .flatMap { ReleaseCheck.isProjectPage($0.page) && ReleaseCheck.isNewer($0.version, than: runningVersion) ? $0 : nil }
    }

    func start() {
        loop = Task { [weak self] in
            try? await Task.sleep(for: Self.firstCheckDelay)
            while !Task.isCancelled {
                await self?.checkIfDue()
                try? await Task.sleep(for: Self.pollInterval)
            }
        }
    }

    private func checkIfDue() async {
        let last = defaults.object(forKey: Key.lastChecked) as? Date
        guard settings.checkForUpdates, ReleaseCheck.isDue(lastChecked: last, now: .now) else { return }
        switch await checkNow() {
        case let .available(release) where defaults.string(forKey: Key.announced) != release.version:
            defaults.set(release.version, forKey: Key.announced)
            onNewRelease?(release)
        case let .failed(message):
            // Tried again within the hour.
            Log.app.info("Could not check for a newer Bilge: \(message, privacy: .public)")
        case .available, .upToDate:
            break
        }
    }

    @discardableResult
    func checkNow() async -> Outcome {
        var request = URLRequest(url: ReleaseCheck.latestURL, timeoutInterval: Self.requestTimeout)
        request.setValue("application/vnd.github+json", forHTTPHeaderField: "Accept")
        let release: ReleaseCheck.Release?
        do {
            let (data, response) = try await URLSession.shared.data(for: request)
            let status = (response as? HTTPURLResponse)?.statusCode ?? 0
            switch status {
            case 200: release = try ReleaseCheck.latest(from: data)
            // Nothing has been published yet.
            case 404: release = nil
            default: return .failed(String(localized: "GitHub \(status) yanıtını verdi."))
            }
        } catch {
            return .failed(error.localizedDescription)
        }
        let newer = release.flatMap { ReleaseCheck.isNewer($0.version, than: runningVersion) ? $0 : nil }
        defaults.set(Date.now, forKey: Key.lastChecked)
        defaults.set(newer.flatMap { try? JSONEncoder().encode($0) }, forKey: Key.newer)
        available = newer
        return newer.map(Outcome.available) ?? .upToDate(runningVersion)
    }
}
