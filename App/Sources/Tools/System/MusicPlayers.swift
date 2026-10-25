import AppKit
import AsistanCore

/// The music apps Bilge controls by AppleScript, and which of them is open or playing.
enum MusicPlayers {
    static func bundleIdentifier(_ app: MusicApp) -> String {
        switch app {
        case .spotify: "com.spotify.client"
        case .music: "com.apple.Music"
        }
    }

    static func displayName(_ app: MusicApp) -> String {
        switch app {
        case .spotify: "Spotify"
        case .music: String(localized: "Müzik")
        }
    }

    /// In order of preference.
    @MainActor
    static func running() -> [MusicApp] {
        let running = Set(NSWorkspace.shared.runningApplications.compactMap(\.bundleIdentifier))
        return MusicApp.allCases.filter { running.contains(bundleIdentifier($0)) }
    }

    @MainActor
    static func isInstalled(_ app: MusicApp) -> Bool {
        NSWorkspace.shared.urlForApplication(withBundleIdentifier: bundleIdentifier(app)) != nil
    }

    /// Asks every app in `apps` (which must be running: telling a closed app launches it) in one script.
    static func states(of apps: [MusicApp]) async throws -> [MusicPlayerChoice.Player] {
        guard !apps.isEmpty else { return [] }
        let queries = apps.map { app in
            """
            tell application \(AppleScriptRunner.quoted(app.rawValue))
            if player state is playing then
            set end of states to "playing"
            else if player state is paused then
            set end of states to "paused"
            else
            set end of states to "stopped"
            end if
            end tell
            """
        }
        let output = try await AppleScriptRunner.run("""
        set states to {}
        \(queries.joined(separator: "\n"))
        set AppleScript's text item delimiters to linefeed
        return states as text
        """)
        let states = output.split(separator: "\n").map { line -> MusicPlayerChoice.State in
            switch line {
            case "playing": .playing
            case "paused": .paused
            default: .stopped
            }
        }
        return zip(apps, states).map { ($0, $1) }
    }

    /// Skips the query when it could not change the choice.
    static func controlTarget() async throws -> MusicApp? {
        let open = await MainActor.run { running() }
        guard open.count > 1 else { return open.first }
        return MusicPlayerChoice.forControl(try await states(of: open))
    }
}
