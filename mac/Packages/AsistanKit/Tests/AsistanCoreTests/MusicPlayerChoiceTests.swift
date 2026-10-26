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

    @Test("play, pause and play/pause go to the app that is playing")
    func transportToPlayingApp() {
        for action in [MusicPlayerChoice.Transport.play, .pause, .toggle] {
            #expect(MusicPlayerChoice.transportTarget(action, players: [(.spotify, .paused), (.music, .playing)],
                                                      othersSounding: true, mediaTab: true) == .app(.music))
        }
    }

    @Test("a pause presses the play/pause key only while another app is sounding, so it never starts playback")
    func pauseNeverStarts() {
        #expect(MusicPlayerChoice.transportTarget(.pause, players: [(.music, .paused)], othersSounding: true, mediaTab: false) == .mediaKey)
        #expect(MusicPlayerChoice.transportTarget(.pause, players: [(.music, .paused)], othersSounding: false, mediaTab: true) == .nothing)
        #expect(MusicPlayerChoice.transportTarget(.pause, players: [], othersSounding: false, mediaTab: false) == .nothing)
    }

    @Test("resuming: something already sounding is left alone, a browser's music tab comes before a paused track")
    func resume() {
        #expect(MusicPlayerChoice.transportTarget(.play, players: [(.music, .paused)], othersSounding: true, mediaTab: true) == .alreadyPlaying)
        #expect(MusicPlayerChoice.transportTarget(.play, players: [(.music, .paused)], othersSounding: false, mediaTab: true) == .mediaKey)
        #expect(MusicPlayerChoice.transportTarget(.play, players: [(.spotify, .stopped), (.music, .paused)],
                                                  othersSounding: false, mediaTab: false) == .app(.music))
        #expect(MusicPlayerChoice.transportTarget(.play, players: [(.spotify, .stopped)], othersSounding: false, mediaTab: false) == .nothing)
    }

    @Test("play/pause pauses what sounds elsewhere, else resumes like play")
    func toggle() {
        #expect(MusicPlayerChoice.transportTarget(.toggle, players: [(.music, .paused)], othersSounding: true, mediaTab: false) == .mediaKey)
        #expect(MusicPlayerChoice.transportTarget(.toggle, players: [(.music, .paused)], othersSounding: false, mediaTab: false) == .app(.music))
        #expect(MusicPlayerChoice.transportTarget(.toggle, players: [], othersSounding: false, mediaTab: false) == .nothing)
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
