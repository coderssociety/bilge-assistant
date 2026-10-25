import AppKit
import AsistanCore

/// Plays a named song on a service: the first match of the service's keyless search opens where it plays (a YouTube
/// watch page in the default browser, a track in the Deezer app or on its site, a song in Music), and Spotify, which
/// has no such search, shows its own results. When the search fails, the service's search page opens instead.
enum MusicPlayback {
    /// Settings' default service; absent means "Otomatik".
    static let serviceKey = "musicService"
    private static let deezerScheme = "deezer"
    private static let musicStartTimeout: Duration = .seconds(4)
    private static let musicStartPoll: Duration = .milliseconds(500)

    static var preferredService: MusicService? {
        UserDefaults.standard.string(forKey: serviceKey).flatMap(MusicService.init(rawValue:))
    }

    /// "YouTube'da", "Apple Music'te": the service as a place, to begin a reply with.
    static func place(_ service: MusicService) -> String {
        switch service {
        case .spotify: String(localized: "Spotify'da")
        case .appleMusic: String(localized: "Apple Music'te")
        case .youTube: String(localized: "YouTube'da")
        case .youTubeMusic: String(localized: "YouTube Music'te")
        case .deezer: String(localized: "Deezer'da")
        }
    }

    static func play(_ query: String, on service: MusicService) async -> String {
        let language = AppLanguage.current
        let country = language == .english ? "US" : "TR"
        do {
            switch service {
            case .spotify: return await openSpotifySearch(query, country: country)
            case .appleMusic:
                if let reply = try await playFromLibrary(query) { return reply }
            case .youTube, .youTubeMusic, .deezer: break
            }
            guard let track = try await search(query, on: service, language: language, country: country).first else {
                return await openSearchPage(service, query: query, country: country,
                                            reply: String(localized: "\(place(service)) '\(query)' için bir şarkı bulamadım; arama sayfasını açtım."))
            }
            return await open(track, on: service)
        } catch let error as WebFetchError {
            Log.tools.info("Music search failed on \(service.rawValue, privacy: .public): \(error.localizedDescription, privacy: .public)")
            return await openSearchPage(service, query: query, country: country,
                                        reply: String(localized: "\(place(service)) şarkıyı arayamadım; '\(query)' arama sayfasını açtım."))
        } catch {
            return ToolReply.failure(error)
        }
    }

    private static func search(_ query: String, on service: MusicService, language: AssistantLanguage,
                               country: String) async throws -> [MusicTrack] {
        switch service {
        case .youTube: return try await youTubeVideos(query, language: language, country: country)
        case .youTubeMusic:
            let body = MusicSearch.youTubeSearchBody(query, client: .music, language: language.code, country: country)
            let songs = MusicSearch.youTubeMusicSongs(try await WebFetch.post(json: body, to: MusicSearch.YouTubeClient.music.endpoint))
            guard songs.isEmpty else { return songs }
            return try await youTubeVideos(query, language: language, country: country).map(MusicSearch.onYouTubeMusic)
        case .deezer:
            guard let url = MusicSearch.deezerSearchURL(query) else { return [] }
            return MusicSearch.deezerTracks(try await WebFetch.data(from: url))
        case .appleMusic:
            guard let url = MusicSearch.iTunesSearchURL(query, country: country) else { return [] }
            return MusicSearch.iTunesSongs(try await WebFetch.data(from: url))
        case .spotify: return []
        }
    }

    private static func youTubeVideos(_ query: String, language: AssistantLanguage, country: String) async throws -> [MusicTrack] {
        let body = MusicSearch.youTubeSearchBody(query, client: .web, language: language.code, country: country)
        return MusicSearch.youTubeVideos(try await WebFetch.post(json: body, to: MusicSearch.YouTubeClient.web.endpoint))
    }

    private static func open(_ track: MusicTrack, on service: MusicService) async -> String {
        let deezerApp = service == .deezer ? MusicSearch.appURL(track.url, scheme: deezerScheme) : nil
        let deezerInApp = await MainActor.run { deezerApp.flatMap(NSWorkspace.shared.urlForApplication(toOpen:)) != nil }
        let target: URL? = switch service {
        case .appleMusic: MusicSearch.appURL(track.url, scheme: "music")
        case .deezer where deezerInApp: deezerApp
        default: track.url
        }
        guard let target, await openURL(target) else {
            return ToolReply.failure(String(localized: "\(place(service)) '\(track.spoken)' açılamadı."))
        }
        await stopBilgePlayer()
        await MusicPlayers.pauseAll(except: service == .appleMusic ? .music : nil)
        guard service == .appleMusic else { return String(localized: "\(place(service)) '\(track.spoken)' açıldı.") }
        return await musicStarted(track)
            ? String(localized: "Apple Music'te '\(track.spoken)' çalıyor.")
            : String(localized: "Apple Music'te '\(track.spoken)' gösterildi; çalmak için oynat düğmesine basabilirsin.")
    }

    /// Music shows a catalog song it was sent to and may start it; AppleScript cannot play what is not in the library,
    /// so this only waits a moment to tell which happened.
    private static func musicStarted(_ track: MusicTrack) async -> Bool {
        let title = TurkishText.folded(track.title)
        let deadline = ContinuousClock.now + musicStartTimeout
        while ContinuousClock.now < deadline {
            try? await Task.sleep(for: musicStartPoll)
            let playing = try? await AppleScriptRunner.run("""
            tell application "Music"
            if player state is not playing then return ""
            return name of current track
            end tell
            """)
            if let playing, !playing.isEmpty, TurkishText.folded(playing).contains(title) { return true }
        }
        return false
    }

    /// A playlist by name, else the first library track whose name, artist or album says the query.
    private static func playFromLibrary(_ query: String) async throws -> String? {
        if let playlist = try await matchingPlaylist(query) {
            _ = try await AppleScriptRunner.run("tell application \"Music\" to play playlist \(AppleScriptRunner.quoted(playlist))")
            await stopBilgePlayer()
            await MusicPlayers.pauseAll(except: .music)
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
        guard !playing.isEmpty else { return nil }
        await stopBilgePlayer()
        await MusicPlayers.pauseAll(except: .music)
        return String(localized: "Çalıyorum: \(playing).")
    }

    private static func matchingPlaylist(_ query: String) async throws -> String? {
        let names = try await AppleScriptRunner.run("""
        tell application "Music"
        set AppleScript's text item delimiters to linefeed
        return (name of every user playlist) as text
        end tell
        """)
        return PhraseMatcher.bestMatch(for: query, in: names.split(separator: "\n").map(String.init))
    }

    private static func openSpotifySearch(_ query: String, country: String) async -> String {
        let inApp = await MainActor.run { MusicPlayers.isInstalled(.spotify) }
        let url = inApp ? MusicSearch.spotifySearch(query) : MusicSearch.searchPage(.spotify, query: query, country: country)
        guard let url, await openURL(url) else { return ToolReply.failure(String(localized: "Spotify'da arama açılamadı.")) }
        await stopBilgePlayer()
        return String(localized: "Spotify'da '\(query)' için arama sonuçlarını açtım; çalmak istediğini seçebilirsin.")
    }

    private static func openSearchPage(_ service: MusicService, query: String, country: String, reply: String) async -> String {
        guard let page = MusicSearch.searchPage(service, query: query, country: country), await openURL(page) else {
            return ToolReply.failure(String(localized: "\(place(service)) arama açılamadı."))
        }
        await stopBilgePlayer()
        return reply
    }

    @MainActor
    private static func openURL(_ url: URL) -> Bool {
        NSWorkspace.shared.open(url)
    }

    /// Radio or a podcast in Bilge would talk over the music and keep "durdur" for itself.
    @MainActor
    private static func stopBilgePlayer() {
        StreamPlayer.shared.stop()
    }
}
