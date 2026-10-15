import AsistanCore
import Foundation
import FoundationModels

/// Plays a song, artist, album or playlist from the Music library. Apple Music catalog and Spotify
/// search are not scriptable, so only what is in the library can be found.
struct PlayMusicTool: AssistantTool {
    let name = "playMusic"
    let description = "Müzik uygulamasında adı söylenen şarkıyı, sanatçıyı, albümü ya da çalma listesini çalar."

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
