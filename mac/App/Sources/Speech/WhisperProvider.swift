import AsistanCore
import Foundation

/// The one Whisper recognizer the app loads, shared by listening (when Whisper is the chosen engine) and by
/// sessions that need it whatever the engine: interpreting (language detection) and meeting transcription.
@MainActor
final class WhisperProvider {
    private let language: AssistantLanguage
    private var recognizer: (any SpeechRecognizer)?
    private var loading: Task<any SpeechRecognizer, any Error>?
    /// Listening uses it too, so it is not unloaded when a session ends.
    var isListeningEngine = false

    init(language: AssistantLanguage) {
        self.language = language
    }

    /// Loaded, or on disk; sessions never start the 1.5 GB download themselves.
    var isAvailable: Bool { recognizer != nil || WhisperKitRecognizer.isDownloaded }

    var loaded: (any SpeechRecognizer)? { recognizer }

    /// What to say when a session needs Whisper and it is not on this Mac.
    static var missingMessage: String {
        String(localized: "Bunun için Whisper konuşma tanıma modeli gerekiyor. Ayarlar > Tanıma bölümünden Whisper'ı bir kez seçip indirebilirsin.")
    }

    func prepared() async throws -> any SpeechRecognizer {
        if let recognizer { return recognizer }
        if let loading { return try await loading.value }
        let language = language
        let task = Task<any SpeechRecognizer, any Error> {
            let recognizer = RecognizerFactory.make(.whisper, language: language)
            try await recognizer.prepare()
            return recognizer
        }
        loading = task
        defer { loading = nil }
        let prepared = try await task.value
        recognizer = prepared
        return prepared
    }

    /// Frees the model's memory after a session, unless listening needs it.
    func releaseUnlessListening() {
        guard !isListeningEngine, loading == nil else { return }
        recognizer = nil
    }
}
