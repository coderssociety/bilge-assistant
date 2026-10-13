import AsistanCore
import Foundation

enum LMStudioError: LocalizedError {
    case notInstalled
    case serverUnavailable
    case loadFailed(String)
    case badResponse(Int)

    var errorDescription: String? {
        switch self {
        case .notInstalled: "LM Studio bulunamadı."
        case .serverUnavailable: "LM Studio sunucusu başlatılamadı."
        case let .loadFailed(detail): "Model yüklenemedi: \(detail)"
        case let .badResponse(status): "LM Studio beklenmeyen bir yanıt verdi (\(status))."
        }
    }
}

/// Talks to the LM Studio server on this Mac. The address is fixed to loopback so conversations
/// never leave the machine, whatever the server's own network setting is.
struct LMStudioClient: Sendable {
    struct Model: Decodable, Sendable, Identifiable, Hashable {
        let id: String
        let type: String
        let arch: String?
        let quantization: String?
        let state: String

        var isLoaded: Bool { state == "loaded" }
        var isChatModel: Bool { type == "llm" || type == "vlm" }
        /// Qwen templates think before answering unless the prompt closes the reasoning block itself.
        var usesChatML: Bool { arch?.hasPrefix("qwen") ?? false }
    }

    private struct ModelList: Decodable { let data: [Model] }

    private static let baseURL = URL(string: "http://127.0.0.1:1234")!
    private static let contextLength = 8192
    private static let loadTimeout: Duration = .seconds(240)
    private static let requestTimeout: TimeInterval = 60
    private static let startupPolls = 10

    static var commandLineTool: URL {
        FileManager.default.homeDirectoryForCurrentUser.appending(path: ".lmstudio/bin/lms")
    }

    static var isInstalled: Bool {
        FileManager.default.isExecutableFile(atPath: commandLineTool.path(percentEncoded: false))
    }

    func chatModels() async throws -> [Model] {
        let (data, response) = try await URLSession.shared.data(from: Self.baseURL.appending(path: "api/v0/models"))
        try Self.check(response)
        return try JSONDecoder().decode(ModelList.self, from: data).data.filter(\.isChatModel)
    }

    /// Starts the server and loads the model when needed. Loading a large model takes 15–30 s.
    func startServerIfNeeded() async throws {
        guard Self.isInstalled else { throw LMStudioError.notInstalled }
        if (try? await chatModels()) != nil { return }
        try Task.checkCancellation()
        try await runTool(["server", "start"], timeout: .seconds(30))
        for _ in 0..<Self.startupPolls {
            if (try? await chatModels()) != nil { return }
            try await Task.sleep(for: .milliseconds(500))
        }
        throw LMStudioError.serverUnavailable
    }

    func prepare(_ id: String) async throws -> Model {
        try await startServerIfNeeded()
        guard let models = try? await chatModels() else { throw LMStudioError.serverUnavailable }
        guard let model = models.first(where: { $0.id == id }) else {
            throw LMStudioError.loadFailed("\(id) LM Studio'da yok.")
        }
        if model.isLoaded { return model }
        Log.brain.info("Loading \(id, privacy: .public) in LM Studio")
        try await runTool(["load", id, "--context-length", String(Self.contextLength), "-y"], timeout: Self.loadTimeout)
        guard let loaded = try await chatModels().first(where: { $0.id == id }), loaded.isLoaded else {
            throw LMStudioError.loadFailed(id)
        }
        return loaded
    }

    /// Streams the reply text. A separate `reasoning_content` field is ignored; non-Qwen models are
    /// expected to answer without inline reasoning.
    func streamReply(
        model: Model,
        messages: [ChatMessage],
        temperature: Double,
        maxTokens: Int
    ) -> AsyncThrowingStream<String, any Error> {
        AsyncThrowingStream { continuation in
            let task = Task {
                do {
                    let request = try makeRequest(model: model, messages: messages, temperature: temperature, maxTokens: maxTokens)
                    let (bytes, response) = try await URLSession.shared.bytes(for: request)
                    try Self.check(response)
                    for try await line in bytes.lines {
                        switch ServerSentEventLine(line) {
                        case .ignored: continue
                        case .done: continuation.finish(); return
                        case let .data(payload):
                            if let text = try Self.text(in: payload, chatML: model.usesChatML), !text.isEmpty {
                                continuation.yield(text)
                            }
                        }
                    }
                    continuation.finish()
                } catch {
                    continuation.finish(throwing: error)
                }
            }
            continuation.onTermination = { _ in task.cancel() }
        }
    }

    private func makeRequest(model: Model, messages: [ChatMessage], temperature: Double, maxTokens: Int) throws -> URLRequest {
        var body: [String: Any] = ["model": model.id, "stream": true, "temperature": temperature, "max_tokens": maxTokens]
        let path: String
        if model.usesChatML {
            path = "v1/completions"
            body["prompt"] = ChatMLPrompt.render(messages)
            body["stop"] = ChatMLPrompt.stopSequences
        } else {
            path = "v1/chat/completions"
            body["messages"] = messages.map { ["role": $0.role.rawValue, "content": $0.content] }
        }
        var request = URLRequest(url: Self.baseURL.appending(path: path), timeoutInterval: Self.requestTimeout)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = try JSONSerialization.data(withJSONObject: body)
        return request
    }

    private static func text(in payload: String, chatML: Bool) throws -> String? {
        struct Chunk: Decodable {
            struct Choice: Decodable {
                struct Delta: Decodable { let content: String? }
                let text: String?
                let delta: Delta?
            }
            let choices: [Choice]
        }
        let choice = try JSONDecoder().decode(Chunk.self, from: Data(payload.utf8)).choices.first
        return chatML ? choice?.text : choice?.delta?.content
    }

    private static func check(_ response: URLResponse) throws {
        guard let status = (response as? HTTPURLResponse)?.statusCode else { return }
        guard (200..<300).contains(status) else { throw LMStudioError.badResponse(status) }
    }

    private func runTool(_ arguments: [String], timeout: Duration) async throws {
        let output = try await ProcessRunner.run(Self.commandLineTool.path(percentEncoded: false), arguments, timeout: timeout)
        guard output.status == 0 else {
            Log.brain.error("lms \(arguments.first ?? "", privacy: .public) failed: \(output.standardError, privacy: .public)")
            throw LMStudioError.loadFailed(output.standardError.isEmpty ? "lms \(output.status)" : output.standardError)
        }
    }
}
