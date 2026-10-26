import AppKit
import AsistanCore
import FoundationModels

/// Plays a song, artist, album or playlist on the service set in Settings; "Otomatik" picks the app that is playing,
/// else Spotify when it is open or installed, else Music (see `MusicPlayback`).
struct PlayMusicTool: AssistantTool {
    let name = "playMusic"
    let description = "Adı söylenen şarkıyı, sanatçıyı, albümü ya da çalma listesini ayarlardaki müzik servisinde (Spotify, Müzik, YouTube, YouTube Music, Deezer) çalar."

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
            let service = try await MusicService.forRequest(named: nil, preferred: MusicPlayback.preferredService,
                                                            automatic: Self.automaticApp)
            return await MusicPlayback.play(query, on: service)
        } catch {
            return ToolReply.failure(error)
        }
    }

    private static func automaticApp() async throws -> MusicApp {
        let (open, spotifyInstalled) = await MainActor.run { (MusicPlayers.running(), MusicPlayers.isInstalled(.spotify)) }
        let players = open.count > 1
            ? try await MusicPlayers.states(of: open)
            : open.map { ($0, MusicPlayerChoice.State.stopped) }
        return MusicPlayerChoice.forSearch(players, spotifyInstalled: spotifyInstalled)
    }
}

/// "YouTube'da Tarkan aç", "YouTube Music'te Sezen Aksu çal", "play Kuzu Kuzu on Deezer": a song on the service named,
/// whatever the setting. Routed by rule, as the model would open the service's site instead.
struct PlayMusicOnServiceTool: RuleRoutedTool {
    let name = "playMusicOnService"
    let description = "Adı söylenen şarkıyı ya da sanatçıyı söylenen serviste (YouTube, YouTube Music, Deezer, Spotify, Apple Music) çalar."

    @Generable
    struct Arguments {
        @Guide(description: "Kullanıcının isteği, olduğu gibi")
        var request: String
    }

    @MainActor
    func claims(_ command: String) -> Bool {
        MusicRequest.parse(command) != nil
    }

    func arguments(fromCommand command: String) -> Arguments? {
        Arguments(request: command)
    }

    func call(arguments: Arguments) async throws -> String {
        guard let request = MusicRequest.parse(arguments.request) else {
            return ToolReply.failure(String(localized: "Ne çalmamı istediğini anlayamadım."))
        }
        return await MusicPlayback.play(request.query, on: request.service)
    }
}
