import AsistanCore
import Foundation

/// Keeps a recognizer from answering noise: a recording with nothing standing out from its own background is not
/// transcribed at all, and the closing lines of videos Whisper invents for near-silence are taken out of what comes
/// back.
actor GuardedRecognizer: SpeechRecognizer {
    nonisolated let engine: RecognizerEngine
    private let inner: any SpeechRecognizer

    init(_ inner: any SpeechRecognizer) {
        self.inner = inner
        engine = inner.engine
    }

    func prepare() async throws {
        try await inner.prepare()
    }

    func transcribe(_ samples: [Float]) async throws -> String {
        guard Loudness.holdsSpeech(samples, sampleRate: StreamingResampler.targetSampleRate) else {
            Log.speech.debug("Not transcribed: nothing louder than the background")
            return ""
        }
        return MadeUpSentences.removed(from: try await inner.transcribe(samples))
    }
}
