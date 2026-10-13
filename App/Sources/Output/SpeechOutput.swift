import AsistanCore
import FluidAudio

/// Turkish voice output: normalizes text, synthesizes sentence by sentence with Supertonic-3 and
/// queues each sentence as soon as it is ready, so the first words play while later ones are rendered.
@MainActor
final class SpeechOutput {
    static let language = "tr"
    static let sampleRate: Double = 44_100

    private let player = AudioPlayer(sampleRate: sampleRate)
    private var manager: Supertonic3Manager?
    private var style: Supertonic3VoiceStyle?
    private(set) var voice: Supertonic3Voice
    var speed: Float

    init(voice: Supertonic3Voice = .f1, speed: Float = 1.05) {
        self.voice = voice
        self.speed = speed
    }

    var isReady: Bool { manager != nil && style != nil }

    /// Benchmarks synthesize and "play" in real time without making sound.
    var isMuted: Bool {
        get { player.isMuted }
        set { player.isMuted = newValue }
    }
    var isSpeaking: Bool { player.isPlaying }
    var playbackTimeline: PlaybackTimeline { player.timeline }

    func prepare() async throws {
        if manager == nil { manager = try await Supertonic3Manager.downloadAndCreate() }
        if style == nil { style = try await Supertonic3ResourceDownloader.loadVoiceStyle(voice) }
    }

    func setVoice(_ newVoice: Supertonic3Voice) async throws {
        guard newVoice != voice || style == nil else { return }
        style = try await Supertonic3ResourceDownloader.loadVoiceStyle(newVoice)
        voice = newVoice
    }

    func speak(_ text: String) async throws {
        for sentence in SentenceSplitter.split(text) {
            try await enqueue(sentence)
        }
        await player.waitUntilDrained()
    }

    /// Speaks streamed text (e.g. model output) sentence by sentence as fragments arrive.
    func speak<Fragments: AsyncSequence<String, any Error>>(streaming fragments: Fragments) async throws {
        var accumulator = SentenceAccumulator()
        for try await fragment in fragments {
            for sentence in accumulator.append(fragment) { try await enqueue(sentence) }
        }
        for sentence in accumulator.finish() { try await enqueue(sentence) }
        await player.waitUntilDrained()
    }

    func stop() {
        player.stop()
    }

    private func enqueue(_ sentence: String) async throws {
        try await prepare()
        guard let manager, let style else { throw Supertonic3Error.notInitialized }
        let spoken = TurkishSpeechNormalizer.normalize(sentence)
        guard !spoken.isEmpty else { return }
        try Task.checkCancellation()
        let result = try await manager.synthesize(text: spoken, language: Self.language, style: style, speed: speed)
        try Task.checkCancellation()
        try player.enqueue(result.samples)
    }
}
