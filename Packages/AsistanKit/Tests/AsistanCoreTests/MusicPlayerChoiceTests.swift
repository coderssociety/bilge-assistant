import Testing
@testable import AsistanCore

@Suite("MusicPlayerChoice")
struct MusicPlayerChoiceTests {
    @Test("controls the app that is playing, not merely the preferred one")
    func playingWins() {
        #expect(MusicPlayerChoice.forControl([(.spotify, .stopped), (.music, .playing)]) == .music)
        #expect(MusicPlayerChoice.forControl([(.spotify, .playing), (.music, .playing)]) == .spotify)
    }

    @Test("a paused track beats an idle app, so its name can still be told")
    func pausedBeatsIdle() {
        #expect(MusicPlayerChoice.forControl([(.spotify, .stopped), (.music, .paused)]) == .music)
    }

    @Test("falls back to the first running app, and to none")
    func fallback() {
        #expect(MusicPlayerChoice.forControl([(.spotify, .stopped), (.music, .stopped)]) == .spotify)
        #expect(MusicPlayerChoice.forControl([]) == nil)
    }

    @Test("play controls go to the playing app, else to the media keys")
    func transport() {
        #expect(MusicPlayerChoice.forTransport([(.spotify, .paused), (.music, .playing)], resuming: false) == .music)
        #expect(MusicPlayerChoice.forTransport([(.music, .paused)], resuming: false) == nil)
        #expect(MusicPlayerChoice.forTransport([(.music, .paused)], resuming: true) == .music)
        #expect(MusicPlayerChoice.forTransport([(.spotify, .stopped)], resuming: true) == nil)
        #expect(MusicPlayerChoice.forTransport([], resuming: true) == nil)
    }

    @Test("searches where music is playing, then in Spotify when it is open or Music is not")
    func search() {
        #expect(MusicPlayerChoice.forSearch([(.spotify, .stopped), (.music, .playing)], spotifyInstalled: true) == .music)
        #expect(MusicPlayerChoice.forSearch([(.spotify, .stopped)], spotifyInstalled: true) == .spotify)
        #expect(MusicPlayerChoice.forSearch([], spotifyInstalled: true) == .spotify)
        #expect(MusicPlayerChoice.forSearch([], spotifyInstalled: false) == .music)
        #expect(MusicPlayerChoice.forSearch([(.music, .stopped)], spotifyInstalled: true) == .music)
    }
}
