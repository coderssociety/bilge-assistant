import AsistanCore

/// Listens while the assistant is speaking: echo-cancels the microphone against the speaker
/// output, finds utterances, transcribes them and reports when the user cuts in.
@MainActor
final class BargeInListener {
    typealias DecisionHandler = @MainActor (BargeInDetector.Decision, String) -> Void

    private let echo: EchoCanceller
    private let vad: VoiceActivityMonitor
    private let timeline: PlaybackTimeline
    private let recognizer: any SpeechRecognizer
    private let detector: BargeInDetector
    /// Stricter than normal listening: residual echo must not open a segment on its own.
    private var segmenter = SpeechSegmenter(configuration: .init(
        chunkDuration: VoiceActivityFrame.duration, startThreshold: 0.75, endThreshold: 0.4,
        minSilence: 0.45, preRoll: 0.3, minSpeech: 0.3, maxSegment: 5))
    private var transcription: Task<Void, Never>?

    init(timeline: PlaybackTimeline, recognizer: any SpeechRecognizer, detector: BargeInDetector) async throws {
        echo = try await EchoCanceller()
        vad = try await VoiceActivityMonitor()
        self.timeline = timeline
        self.recognizer = recognizer
        self.detector = detector
    }

    func reset() async {
        transcription?.cancel()
        transcription = nil
        segmenter.reset()
        await vad.reset()
        do {
            try await echo.reset()
        } catch {
            Log.audio.error("Echo canceller reset failed: \(error.localizedDescription, privacy: .public)")
        }
    }

    func listen(_ chunk: AudioChunk, replySoFar: String, onDecision: @escaping DecisionHandler) async {
        let reference = timeline.samples(from: chunk.startSeconds, count: chunk.samples.count)
        do {
            let cleaned = try await echo.process(mic: chunk.samples, reference: reference)
            for frame in try await vad.process(cleaned) {
                for segment in segmenter.process(frame.samples, probability: frame.probability) {
                    evaluate(segment.samples, replySoFar: replySoFar, onDecision: onDecision)
                }
            }
        } catch {
            Log.audio.error("Barge-in processing failed: \(error.localizedDescription, privacy: .public)")
        }
    }

    /// One transcription at a time; utterances arriving meanwhile are dropped, not queued,
    /// so a stale "dur" never stops the next reply.
    private func evaluate(_ samples: [Float], replySoFar: String, onDecision: @escaping DecisionHandler) {
        guard transcription == nil else { return }
        let recognizer = recognizer
        let detector = detector
        transcription = Task {
            defer { transcription = nil }
            do {
                let heard = try await recognizer.transcribe(samples)
                guard !Task.isCancelled else { return }
                let decision = detector.evaluate(heard: heard, speaking: replySoFar)
                Log.wake.debug("Barge-in heard: \(heard, privacy: .private) → \(String(describing: decision), privacy: .public)")
                if decision != .none { onDecision(decision, heard) }
            } catch {
                Log.speech.error("Barge-in transcription failed: \(error.localizedDescription, privacy: .public)")
            }
        }
    }
}
