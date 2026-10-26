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

    /// Something else has started (radio or a podcast in Bilge, a song on a service); Music and Spotify stop talking
    /// over it, except `kept`, the app that was just started.
    static func pauseAll(except kept: MusicApp? = nil) async {
        let open = await MainActor.run { running() }.filter { $0 != kept }
        guard !open.isEmpty else { return }
        do {
            for player in try await states(of: open) where player.state == .playing {
                _ = try await AppleScriptRunner.run("tell application \(AppleScriptRunner.quoted(player.app.rawValue)) to pause")
            }
        } catch {
            Log.tools.error("Could not pause the music apps: \(error.localizedDescription, privacy: .public)")
        }
    }

    /// Whether Music or Spotify has a track playing or paused, which a bare "devam et" would resume. False when they
    /// cannot be asked, so Bilge's own player gets the command.
    static func holdsTrack() async -> Bool {
        let open = await MainActor.run { running() }
        guard !open.isEmpty else { return false }
        do {
            return try await states(of: open).contains { $0.state != .stopped }
        } catch {
            Log.tools.error("Could not ask the music apps: \(error.localizedDescription, privacy: .public)")
            return false
        }
    }

    /// Skips the query when it could not change the choice.
    static func controlTarget() async throws -> MusicApp? {
        let open = await MainActor.run { running() }
        guard open.count > 1 else { return open.first }
        return MusicPlayerChoice.forControl(try await states(of: open))
    }
}
