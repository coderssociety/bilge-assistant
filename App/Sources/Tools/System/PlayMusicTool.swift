import AppKit
import AsistanCore
import FoundationModels

/// Plays a song, artist, album or playlist from the Music library, or opens a Spotify search for it.
/// The Apple Music catalog is not scriptable, and Spotify's AppleScript cannot search, so Music only
/// finds what is in the library and Spotify shows the results without playing one.
struct PlayMusicTool: AssistantTool {
    let name = "playMusic"
    let description = "Adı söylenen şarkıyı, sanatçıyı, albümü ya da çalma listesini Spotify'da ya da Müzik uygulamasında çalar."
    private static let spotifySearchAllowed = CharacterSet(charactersIn: "abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789")

    @Generable
    struct Arguments {
        @Guide(description: "Şarkı, sanatçı, albüm ya da çalma listesi adı, eksiz: 'Tarkan'dan' → 'Tarkan'")
        var query: String
    }

    func call(arguments: Arguments) async throws -> String {
        let query = arguments.query.trimmingCharacters(in: .whitespaces)
        guard !query.isEmpty else {
            return ToolReply.failure(String(localized: "Ne çalmamı istediğini anlayamadım."))
        }
        do {
            if try await Self.source() == .spotify {
                return await Self.openSpotifySearch(query)
                    ? String(localized: "Spotify'da '\(query)' için arama sonuçlarını açtım; çalmak istediğini seçebilirsin.")
                    : ToolReply.failure(String(localized: "Spotify'da arama açılamadı."))
            }
            if let playlist = try await matchingPlaylist(query) {
                _ = try await AppleScriptRunner.run("tell application \"Music\" to play playlist \(AppleScriptRunner.quoted(playlist))")
                return String(localized: "'\(playlist)' çalma listesini çalıyorum.")
            }
            let playing = try await AppleScriptRunner.run("""
            tell application "Music"
            set q to \(AppleScriptRunner.quoted(query))
            set found to (every track of library playlist 1 whose name contains q or artist contains q or album contains q)
            if (count of found) = 0 then return ""
            play item 1 of found
            return (name of item 1 of found) & " — " & (artist of item 1 of found)
            end tell
            """)
            guard !playing.isEmpty else {
                return ToolReply.failure(String(localized: "Müzik kitaplığında '\(query)' bulamadım."))
            }
            return String(localized: "Çalıyorum: \(playing).")
        } catch {
            return ToolReply.failure(error)
        }
    }

    private static func source() async throws -> MusicApp {
        let (open, spotifyInstalled) = await MainActor.run { (MusicPlayers.running(), MusicPlayers.isInstalled(.spotify)) }
        let players = open.count > 1
            ? try await MusicPlayers.states(of: open)
            : open.map { ($0, MusicPlayerChoice.State.stopped) }
        return MusicPlayerChoice.forSearch(players, spotifyInstalled: spotifyInstalled)
    }

    @MainActor
    private static func openSpotifySearch(_ query: String) -> Bool {
        guard let encoded = query.addingPercentEncoding(withAllowedCharacters: spotifySearchAllowed),
              let url = URL(string: "spotify:search:" + encoded) else { return false }
        return NSWorkspace.shared.open(url)
    }

    private func matchingPlaylist(_ query: String) async throws -> String? {
        let names = try await AppleScriptRunner.run("""
        tell application "Music"
        set AppleScript's text item delimiters to linefeed
        return (name of every user playlist) as text
        end tell
        """)
        return PhraseMatcher.bestMatch(for: query, in: names.split(separator: "\n").map(String.init))
    }
}
