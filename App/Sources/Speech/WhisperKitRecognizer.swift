import AsistanCore
import Foundation
@preconcurrency import WhisperKit

actor WhisperKitRecognizer: SpeechRecognizer {
    /// Exact folder in argmaxinc/whisperkit-coreml; WhisperKit matches it as "*<name>/*".
    static let modelName = "openai_whisper-large-v3-v20240930_turbo"

    nonisolated let engine = RecognizerEngine.whisper
    private let language: AssistantLanguage
    private var pipeline: WhisperKit?

    init(language: AssistantLanguage) {
        self.language = language
    }

    private var decodingOptions: DecodingOptions {
        var options = DecodingOptions()
        options.language = language.code
        options.detectLanguage = false
        options.temperature = 0
        options.usePrefillPrompt = true
        options.skipSpecialTokens = true
        options.withoutTimestamps = true
        return options
    }

    func prepare() async throws {
        guard pipeline == nil else { return }
        let config = WhisperKitConfig(
            model: Self.modelName,
            downloadBase: try ModelStorage.directory(for: "whisperkit"),
            verbose: false,
            logLevel: .error,
            prewarm: true,
            load: true,
            download: true)
        let started = Date()
        pipeline = try await WhisperKit(config)
        Log.speech.info("WhisperKit ready in \(Date.now.timeIntervalSince(started), format: .fixed(precision: 2)) s")
    }

    func transcribe(_ samples: [Float]) async throws -> String {
        guard let pipeline else { throw RecognizerError.notPrepared }
        let results = try await pipeline.transcribe(audioArray: samples, decodeOptions: decodingOptions)
        return results.map(\.text).joined(separator: " ").trimmingCharacters(in: .whitespacesAndNewlines)
    }
}
