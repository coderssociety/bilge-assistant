import AsistanCore
import Foundation

/// OpenAI's or Groq's transcription API with the user's key. While Bilge waits for its name nothing reaches it: the
/// phrase is heard by a recognizer on the Mac first (see `AssistantController`). What is said once Bilge is listening
/// (the command, a follow-up, a yes, dictation) goes to the service.
actor CloudSpeechRecognizer: SpeechRecognizer {
    nonisolated let engine: RecognizerEngine
    private let service: CloudTranscription
    private let language: AssistantLanguage
    private var apiKey: String?

    private static let timeout: TimeInterval = 30

    init(engine: RecognizerEngine, service: CloudTranscription, language: AssistantLanguage) {
        self.engine = engine
        self.service = service
        self.language = language
    }

    func prepare() async throws {
        guard let key = try Keychain.read(service.service.keyAccount), !key.isEmpty else {
            throw APIModelError.noKey(service.service.name)
        }
        apiKey = key
    }

    func transcribe(_ samples: [Float]) async throws -> String {
        guard let apiKey else { throw RecognizerError.notPrepared }
        let form = service.request(samples: samples, sampleRate: Int(StreamingResampler.targetSampleRate),
                                   language: language.code, apiKey: apiKey, boundary: UUID().uuidString)
        var request = URLRequest(url: service.url, timeoutInterval: Self.timeout)
        request.httpMethod = "POST"
        for (field, value) in form.headers { request.setValue(value, forHTTPHeaderField: field) }
        let (data, response) = try await APISession.shared.upload(for: request, from: form.body)
        try APIModelEndpoint.check(response, body: data, api: service.service)
        return try CloudTranscription.text(inResponse: data)
    }
}
