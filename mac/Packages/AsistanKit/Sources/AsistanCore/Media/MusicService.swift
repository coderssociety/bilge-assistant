/// A service a song can be played on: named in a command ("YouTube'da") or set as the default in Settings.
public enum MusicService: String, Sendable, CaseIterable {
    case spotify, appleMusic, youTube, youTubeMusic, deezer

    public var name: String {
        switch self {
        case .spotify: "Spotify"
        case .appleMusic: "Apple Music"
        case .youTube: "YouTube"
        case .youTubeMusic: "YouTube Music"
        case .deezer: "Deezer"
        }
    }

    public init(_ app: MusicApp) {
        self = app == .spotify ? .spotify : .appleMusic
    }

    /// The service said, else the one set; with neither ("Otomatik"), the app `automatic` picks
    /// (`MusicPlayerChoice.forSearch`), which is only asked then, as asking may run AppleScript.
    public static func forRequest(named: MusicService?, preferred: MusicService?,
                                  automatic: () async throws -> MusicApp) async rethrows -> MusicService {
        if let service = named ?? preferred { return service }
        return MusicService(try await automatic())
    }
}
