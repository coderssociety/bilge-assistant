public enum MusicApp: String, Sendable, CaseIterable {
    case spotify = "Spotify"
    case music = "Music"
}

/// Which music app a command goes to when more than one may be open. Spotify left idle in the
/// background while Music played once took "müziği durdur", and Music kept playing.
public enum MusicPlayerChoice {
    public enum State: Sendable, Equatable { case playing, paused, stopped }

    public typealias Player = (app: MusicApp, state: State)

    /// `running` is in order of preference. The app that is playing wins, then one holding a paused
    /// track (so "bu hangi şarkı" and "devam et" reach it), then the first.
    public static func forControl(_ running: [Player]) -> MusicApp? {
        running.first { $0.state == .playing }?.app
            ?? running.first { $0.state == .paused }?.app
            ?? running.first?.app
    }

    public enum Transport: Sendable { case play, pause, toggle }

    public enum TransportTarget: Sendable, Equatable {
        case app(MusicApp)
        /// The play/pause key, which reaches the app macOS last played sound from: a browser, a podcast app.
        case mediaKey
        /// Something other than Music and Spotify is already sounding, and the key would pause it.
        case alreadyPlaying
        case nothing
    }

    /// Where play, pause and play/pause go. The key is a toggle, so it is pressed to pause only while another app
    /// (`othersSounding`) is making sound, and to resume only when that app is silent: a pause never starts music.
    /// `mediaTab`: a browser has a YouTube, Deezer… tab, which the key resumes before a paused track in Music.
    public static func transportTarget(_ action: Transport, players: [Player], othersSounding: Bool,
                                       mediaTab: Bool) -> TransportTarget {
        if let playing = players.first(where: { $0.state == .playing }) { return .app(playing.app) }
        switch action {
        case .pause: return othersSounding ? .mediaKey : .nothing
        case .toggle where othersSounding: return .mediaKey
        case .play where othersSounding: return .alreadyPlaying
        case .play, .toggle: break
        }
        if mediaTab { return .mediaKey }
        return players.first { $0.state == .paused }.map { .app($0.app) } ?? .nothing
    }

    /// Where a named song is played: the app that is playing, else Spotify when it is open, or when
    /// Music is not open and Spotify is installed, else Music.
    public static func forSearch(_ running: [Player], spotifyInstalled: Bool) -> MusicApp {
        if let playing = running.first(where: { $0.state == .playing }) { return playing.app }
        let open = running.map(\.app)
        return open.contains(.spotify) || (!open.contains(.music) && spotifyInstalled) ? .spotify : .music
    }
}
