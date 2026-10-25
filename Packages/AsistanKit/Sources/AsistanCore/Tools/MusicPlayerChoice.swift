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

    /// Play, pause, next and previous go by AppleScript to the app that is playing (or, to resume, holds a
    /// paused track); nil means neither is, so the media keys reach whatever is: a browser, a podcast app.
    public static func forTransport(_ running: [Player], resuming: Bool) -> MusicApp? {
        running.first { $0.state == .playing }?.app
            ?? (resuming ? running.first { $0.state == .paused }?.app : nil)
    }

    /// Where a named song is played: the app that is playing, else Spotify when it is open, or when
    /// Music is not open and Spotify is installed, else Music.
    public static func forSearch(_ running: [Player], spotifyInstalled: Bool) -> MusicApp {
        if let playing = running.first(where: { $0.state == .playing }) { return playing.app }
        let open = running.map(\.app)
        return open.contains(.spotify) || (!open.contains(.music) && spotifyInstalled) ? .spotify : .music
    }
}
