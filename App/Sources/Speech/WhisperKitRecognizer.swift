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

    /// Whether the model is already on this Mac, so using it starts no 1.5 GB download.
    static var isDownloaded: Bool {
        guard let base = try? ModelStorage.directory(for: "whisperkit") else { return false }
        let decoder = base.appending(path: "models/argmaxinc/whisperkit-coreml/\(modelName)/TextDecoder.mlmodelc")
        return FileManager.default.fileExists(atPath: decoder.path)
    }

    private var decodingOptions: DecodingOptions {
        decodingOptions(language: language.code)
    }

    private func decodingOptions(language code: String) -> DecodingOptions {
        var options = DecodingOptions()
        options.language = code
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
        return Self.text(of: results)
    }

    /// Whisper names only its most likely language. When that is one of `languages` the speech is transcribed in
    /// it; otherwise (a short phrase taken for a related language) each candidate is tried and the most confident
    /// transcription wins.
    func transcribe(_ samples: [Float], detectingAmong languages: [String]) async throws -> DetectedSpeech? {
        guard let pipeline else { throw RecognizerError.notPrepared }
        let detected = try? await pipeline.detectLangauge(audioArray: samples).language
        let candidates = detected.map { languages.contains($0) ? [$0] : languages } ?? languages
        var best: (speech: DetectedSpeech, confidence: Float)?
        for code in candidates {
            let results = try await pipeline.transcribe(audioArray: samples, decodeOptions: decodingOptions(language: code))
            let confidence = Self.confidence(of: results)
            if let best, best.confidence >= confidence { continue }
            best = (DetectedSpeech(text: Self.text(of: results), language: code), confidence)
        }
        return best?.speech
    }

    private static func text(of results: [TranscriptionResult]) -> String {
        results.map(\.text).joined(separator: " ").trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private static func confidence(of results: [TranscriptionResult]) -> Float {
        let segments = results.flatMap(\.segments)
        guard !segments.isEmpty else { return -.infinity }
        return segments.map(\.avgLogprob).reduce(0, +) / Float(segments.count)
    }
}
