import Testing
@testable import AsistanCore

@Suite("StreamMediaChoice")
struct StreamMediaChoiceTests {
    private func takes(pausing: Bool, _ stream: StreamState, _ subject: MediaSubject = .unnamed,
                       musicHoldsTrack: Bool = false) async -> Bool {
        await StreamMediaChoice.takes(pausing: pausing, stream: stream, subject: subject, musicHoldsTrack: { musicHoldsTrack })
    }

    @Test("commands name the music, the radio or podcast, or neither", arguments: [
        ("müziği durdur", MediaSubject.music), ("müziğe devam et", .music), ("Spotify'ı duraklat", .music),
        ("pause the music", .music), ("podcast'i aç", .stream), ("radyoyu duraklat", .stream), ("bölümü geri sar", .stream),
        ("pause the podcast", .stream), ("durdur", .unnamed), ("devam et", .unnamed), ("bu şarkının adı ne", .unnamed),
    ])
    func subject(command: String, expected: MediaSubject) {
        #expect(MediaSubject(command) == expected)
    }

    @Test("a playing stream takes unnamed commands")
    func playing() async {
        #expect(await takes(pausing: true, .playing, musicHoldsTrack: true))
        #expect(await takes(pausing: false, .playing, musicHoldsTrack: true))
    }

    @Test("a paused stream never takes a pause, which belongs to the music playing")
    func pausedPause() async {
        #expect(await !takes(pausing: true, .paused))
        #expect(await !takes(pausing: true, .paused, musicHoldsTrack: true))
    }

    @Test("a paused stream resumes only when no music app holds a track")
    func pausedResume() async {
        #expect(await takes(pausing: false, .paused))
        #expect(await !takes(pausing: false, .paused, musicHoldsTrack: true))
    }

    @Test("naming the music always skips the stream; naming the stream takes it while one is open")
    func named() async {
        #expect(await !takes(pausing: true, .playing, .music))
        #expect(await !takes(pausing: false, .paused, .music))
        #expect(await takes(pausing: false, .paused, .stream, musicHoldsTrack: true))
        #expect(await takes(pausing: true, .paused, .stream))
        #expect(await !takes(pausing: false, .idle, .stream))
        #expect(await !takes(pausing: false, .idle))
    }
}
