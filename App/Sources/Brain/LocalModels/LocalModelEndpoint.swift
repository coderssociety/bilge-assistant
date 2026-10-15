import AsistanCore
import Foundation

enum LocalModelServerError: LocalizedError {
    case notInstalled(String)
    case serverUnavailable(String)
    case loadFailed(String)
    case badResponse(Int)

    var errorDescription: String? {
        switch self {
        case let .notInstalled(server): "\(server) bulunamadı."
        case let .serverUnavailable(server): "\(server) sunucusu başlatılamadı."
        case let .loadFailed(detail): "Model yüklenemedi: \(detail)"
        case let .badResponse(status): "Model sunucusu beklenmeyen bir yanıt verdi (\(status))."
        }
    }
}

/// A loaded model behind an OpenAI-compatible server on this Mac. Addresses are always loopback,
/// so conversations never leave the machine whatever the server's own network setting is.
struct LocalModelEndpoint: LoadedChatModel, Hashable {
    enum PromptStyle: Sendable, Hashable {
        /// Raw ChatML through /v1/completions with reasoning closed: LM Studio ignores
        /// `enable_thinking`, and Qwen would otherwise think for seconds before answering.
        case chatML
        /// /v1/chat/completions; `disablesThinking` sends `enable_thinking: false` to the template.
        case chat(disablesThinking: Bool)
    }

    let baseURL: URL
    let modelID: String
    let promptStyle: PromptStyle

    private static let requestTimeout: TimeInterval = 60

    /// A separate `reasoning_content` field is ignored.
    func streamReply(messages: [ChatMessage], temperature: Double, maxTokens: Int) -> AsyncThrowingStream<String, any Error> {
        AsyncThrowingStream { continuation in
            let task = Task {
                do {
                    let (bytes, response) = try await URLSession.shared.bytes(
                        for: makeRequest(messages: messages, temperature: temperature, maxTokens: maxTokens, stream: true))
                    try Self.check(response)
                    for try await line in bytes.lines {
                        switch ServerSentEventLine(line) {
                        case .ignored: continue
                        case .done: continuation.finish(); return
                        case let .data(payload):
                            if let text = try text(in: payload), !text.isEmpty { continuation.yield(text) }
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

    /// A one-token request: the first generation after a load pays one-off setup (about 1 s), better
    /// spent while the user is still speaking. Sending the real instructions lets the server's prompt
    /// cache reuse them for the first actual question.
    func warmUp(instructions: String) async throws {
        let request = try makeRequest(messages: [.system(instructions), .user("Merhaba")], temperature: 0, maxTokens: 1, stream: false)
        let (_, response) = try await URLSession.shared.data(for: request)
        try Self.check(response)
    }

    static func check(_ response: URLResponse) throws {
        guard let status = (response as? HTTPURLResponse)?.statusCode else { return }
        guard (200..<300).contains(status) else { throw LocalModelServerError.badResponse(status) }
    }

    private func makeRequest(messages: [ChatMessage], temperature: Double, maxTokens: Int, stream: Bool) throws -> URLRequest {
        var body: [String: Any] = ["model": modelID, "stream": stream, "temperature": temperature, "max_tokens": maxTokens]
        let path: String
        switch promptStyle {
        case .chatML:
            path = "v1/completions"
            body["prompt"] = ChatMLPrompt.render(messages)
            body["stop"] = ChatMLPrompt.stopSequences
        case let .chat(disablesThinking):
            path = "v1/chat/completions"
            body["messages"] = messages.map { ["role": $0.role.rawValue, "content": $0.content] }
            if disablesThinking { body["chat_template_kwargs"] = ["enable_thinking": false] }
        }
        var request = URLRequest(url: baseURL.appending(path: path), timeoutInterval: Self.requestTimeout)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = try JSONSerialization.data(withJSONObject: body)
        return request
    }

    private func text(in payload: String) throws -> String? {
        struct Chunk: Decodable {
            struct Choice: Decodable {
                struct Delta: Decodable { let content: String? }
                let text: String?
                let delta: Delta?
            }
            let choices: [Choice]
        }
        let choice = try JSONDecoder().decode(Chunk.self, from: Data(payload.utf8)).choices.first
        return promptStyle == .chatML ? choice?.text : choice?.delta?.content
    }
}
