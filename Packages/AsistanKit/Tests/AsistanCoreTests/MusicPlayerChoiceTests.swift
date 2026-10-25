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

    @Test("searches where music is playing, then in Spotify when it is open or Music is not")
    func search() {
        #expect(MusicPlayerChoice.forSearch([(.spotify, .stopped), (.music, .playing)], spotifyInstalled: true) == .music)
        #expect(MusicPlayerChoice.forSearch([(.spotify, .stopped)], spotifyInstalled: true) == .spotify)
        #expect(MusicPlayerChoice.forSearch([], spotifyInstalled: true) == .spotify)
        #expect(MusicPlayerChoice.forSearch([], spotifyInstalled: false) == .music)
        #expect(MusicPlayerChoice.forSearch([(.music, .stopped)], spotifyInstalled: true) == .music)
    }
}
