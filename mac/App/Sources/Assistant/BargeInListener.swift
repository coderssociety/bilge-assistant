@preconcurrency import AVFoundation
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
        minSilence: 0.45, preRoll: 0.3, minSpeech: 0.3, maxSegment: 3))
    private var transcription: Task<Void, Never>?
    /// Microphone chunks waiting for their speaker reference to be recorded. Cancelling echo
    /// against a missing (all-zero) reference lets the assistant's own voice straight through.
    private var awaitingReference: [AudioChunk] = []
    private static let maxReferenceWait = 0.25
    /// The newest utterance that arrived while another was being transcribed. Kept (not dropped)
    /// because that busy transcription is often just residual echo; cleared on reset.
    private var waiting: (samples: [Float], reply: String, handler: DecisionHandler)?
    /// Recent transcriptions and decisions, for diagnosing barge-in in tests.
    private(set) var diagnostics: [String] = []
    private static let maxDiagnostics = 40

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
        waiting = nil
        awaitingReference.removeAll()
        segmenter.reset()
        await vad.reset()
        do {
            try await echo.reset()
        } catch {
            Log.audio.error("Echo canceller reset failed: \(error.localizedDescription, privacy: .public)")
        }
    }

    /// Called when playback ends. Residual echo can hold an utterance open until the very end of
    /// the reply, so what the user said is still evaluated rather than discarded by `reset()`.
    func finish(replySoFar: String) async -> (decision: BargeInDetector.Decision, heard: String)? {
        await transcription?.value
        let pending = segmenter.flush()?.samples ?? waiting?.samples
        waiting = nil
        guard let pending else { return nil }
        do {
            let heard = try await recognizer.transcribe(pending)
            let decision = detector.evaluate(heard: heard, speaking: replySoFar)
            note("son \(String(format: "%.1f", Double(pending.count) / 16_000))s “\(heard)” → \(decision)")
            return decision == .none ? nil : (decision, heard)
        } catch {
            Log.speech.error("Final barge-in transcription failed: \(error.localizedDescription, privacy: .public)")
            return nil
        }
    }

    private func note(_ line: String) {
        diagnostics = Array((diagnostics + [line]).suffix(Self.maxDiagnostics))
    }

    func listen(_ chunk: AudioChunk, replySoFar: String, onDecision: @escaping DecisionHandler) async {
        awaitingReference.append(chunk)
        let now = AVAudioTime.seconds(forHostTime: mach_absolute_time())
        while let next = awaitingReference.first {
            let end = next.startSeconds + Double(next.samples.count) / PlaybackTimeline.sampleRate
            guard timeline.coveredUntil >= end || now - end > Self.maxReferenceWait else { break }
            awaitingReference.removeFirst()
            await cancelEchoAndSegment(next, replySoFar: replySoFar, onDecision: onDecision)
        }
    }

    private func cancelEchoAndSegment(_ chunk: AudioChunk, replySoFar: String, onDecision: @escaping DecisionHandler) async {
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

    /// One transcription at a time; while busy only the newest utterance waits its turn.
    private func evaluate(_ samples: [Float], replySoFar: String, onDecision: @escaping DecisionHandler) {
        guard transcription == nil else {
            waiting = (samples, replySoFar, onDecision)
            return
        }
        let recognizer = recognizer
        let detector = detector
        transcription = Task {
            defer {
                transcription = nil
                if let next = waiting {
                    waiting = nil
                    evaluate(next.samples, replySoFar: next.reply, onDecision: next.handler)
                }
            }
            do {
                let heard = try await recognizer.transcribe(samples)
                guard !Task.isCancelled else { return }
                let decision = detector.evaluate(heard: heard, speaking: replySoFar)
                note("\(String(format: "%.1f", Double(samples.count) / 16_000))s “\(heard)” → \(decision)")
                Log.wake.debug("Barge-in heard: \(heard, privacy: .private) → \(String(describing: decision), privacy: .public)")
                if decision != .none { onDecision(decision, heard) }
            } catch {
                Log.speech.error("Barge-in transcription failed: \(error.localizedDescription, privacy: .public)")
            }
        }
    }
}
