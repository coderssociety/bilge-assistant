/// What a media command names: "müziği durdur" is about Music or Spotify, "podcast'i durdur" about Bilge's player,
/// a bare "durdur" about neither.
public enum MediaSubject: Sendable, Equatable {
    case unnamed, music, stream

    /// Only the music itself: "bu şarkının adı ne" asked over the radio is about the song on the radio.
    private static let musicStems = ["muzi", "spotify", "music"]
    private static let streamStems = ["podcast", "radyo", "radio", "bolum", "episode", "station"]

    public init(_ text: String) {
        self.init(foldedWords: SpokenToken.split(text).map(\.folded))
    }

    init(foldedWords words: [String]) {
        let music = words.contains { word in Self.musicStems.contains(where: word.hasPrefix) }
        let stream = words.contains { word in Self.streamStems.contains(where: word.hasPrefix) }
        switch (music, stream) {
        case (true, false): self = .music
        case (false, true): self = .stream
        default: self = .unnamed
        }
    }
}

/// Whether play, pause, seeking or "what is playing" goes to the radio or podcast in Bilge rather than to Music,
/// Spotify or a browser. A podcast paused long ago once took "müziği durdur" while Spotify played, and a later
/// "devam et" started it over the music.
public enum StreamMediaChoice {
    /// A playing stream takes every unnamed command; a paused one only what would resume it, and only while no music
    /// app holds a track of its own (asked lazily, as asking runs AppleScript).
    public static func takes(pausing: Bool, stream: StreamState, subject: MediaSubject,
                             musicHoldsTrack: () async -> Bool) async -> Bool {
        guard stream != .idle, subject != .music else { return false }
        if subject == .stream || stream == .playing { return true }
        guard !pausing else { return false }
        return await !musicHoldsTrack()
    }
}
