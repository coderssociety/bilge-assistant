@preconcurrency import AVFoundation
import AsistanCore
import Speech

/// Apple's on-device dictation model. macOS 27's SpeechTranscriber has no Turkish, DictationTranscriber has both
/// languages. In English it rarely hears a Turkish-pronounced "Bilge" ("Bill", "Build"), even with the word
/// given as context, so English defaults to Whisper.
actor AppleDictationRecognizer: SpeechRecognizer {
    nonisolated let engine = RecognizerEngine.appleDictation
    private let language: AssistantLanguage
    private var locale: Locale?

    init(language: AssistantLanguage) {
        self.language = language
    }
    private var analyzerFormat: AVAudioFormat?

    func prepare() async throws {
        guard locale == nil else { return }
        try await Self.ensureAuthorized()
        guard let supported = await DictationTranscriber.supportedLocale(equivalentTo: language.locale) else {
            throw RecognizerError.localeUnsupported
        }
        let transcriber = Self.makeTranscriber(locale: supported)
        if let request = try await AssetInventory.assetInstallationRequest(supporting: [transcriber]) {
            Log.speech.info("Installing Apple dictation assets for \(supported.identifier, privacy: .public)")
            try await request.downloadAndInstall()
        }
        guard let format = await SpeechAnalyzer.bestAvailableAudioFormat(compatibleWith: [transcriber]) else {
            throw RecognizerError.audioFormatUnavailable
        }
        analyzerFormat = format
        locale = supported
    }

    func transcribe(_ samples: [Float]) async throws -> String {
        guard let locale, let analyzerFormat else { throw RecognizerError.notPrepared }
        let transcriber = Self.makeTranscriber(locale: locale)
        let analyzer = SpeechAnalyzer(modules: [transcriber])
        let buffer = try PCMBuffers.convert(PCMBuffers.mono16k(samples), to: analyzerFormat)

        let collector = Task {
            var parts: [String] = []
            for try await result in transcriber.results {
                parts.append(String(result.text.characters))
            }
            return parts.joined(separator: " ")
        }
        let (input, continuation) = AsyncStream<AnalyzerInput>.makeStream()
        do {
            try await analyzer.start(inputSequence: input)
            continuation.yield(AnalyzerInput(buffer: buffer))
            continuation.finish()
            try await analyzer.finalizeAndFinishThroughEndOfInput()
        } catch {
            continuation.finish()
            collector.cancel()
            await analyzer.cancelAndFinishNow()
            throw error
        }
        return try await collector.value.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private static func makeTranscriber(locale: Locale) -> DictationTranscriber {
        DictationTranscriber(
            locale: locale,
            contentHints: [.shortForm],
            transcriptionOptions: [.punctuation],
            reportingOptions: [],
            attributeOptions: [])
    }

    private static func ensureAuthorized() async throws {
        let status = SFSpeechRecognizer.authorizationStatus()
        let resolved = status == .notDetermined ? await requestAuthorization() : status
        guard resolved == .authorized else { throw RecognizerError.permissionDenied }
    }

    private static func requestAuthorization() async -> SFSpeechRecognizerAuthorizationStatus {
        await withCheckedContinuation { continuation in
            SFSpeechRecognizer.requestAuthorization { continuation.resume(returning: $0) }
        }
    }
}
