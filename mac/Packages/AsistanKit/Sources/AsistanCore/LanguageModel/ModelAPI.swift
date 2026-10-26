import Foundation

public enum ModelAPIError: Error, Equatable, Sendable {
    /// The service reported an error inside an otherwise successful stream.
    case service(String)
    case unexpectedResponse
}

/// A conversation model reached over an HTTP API instead of run by Bilge: a hosted service that takes the
/// user's key (what is said goes to that company), or a server on this Mac (Ollama, llama.cpp).
public struct ModelAPI: Sendable, Hashable {
    public enum Format: Sendable, Hashable {
        /// `/chat/completions`, which every service here except Anthropic offers.
        case openAIChat
        case anthropicMessages
    }

    public static let anthropicVersion = "2023-06-01"
    /// OpenAI's reasoning models count their thinking against `max_completion_tokens`; without room for it a short
    /// spoken answer can come back empty.
    static let reasoningAllowance = 2048
    /// Generous for Turkish and English text; only used to keep the allowance above from lengthening the reply.
    static let charactersPerToken = 4
    /// OpenAI's models from before reasoning, which still take a temperature; the others refuse anything but the
    /// default.
    private static let temperatureModelPrefixes = ["gpt-4", "gpt-3.5", "chatgpt-4o"]

    public let server: LocalModelChoice.Server
    public let name: String
    public let baseURL: URL
    public let format: Format
    /// Hosted by a company: needs the user's key, and the conversation leaves the Mac.
    public let isHosted: Bool

    init?(server: LocalModelChoice.Server) {
        let preset: (String, String, Format, Bool)
        switch server {
        case .openAI: preset = ("OpenAI", "https://api.openai.com/v1", .openAIChat, true)
        case .anthropic: preset = ("Anthropic", "https://api.anthropic.com/v1", .anthropicMessages, true)
        case .gemini: preset = ("Google Gemini", "https://generativelanguage.googleapis.com/v1beta/openai", .openAIChat, true)
        case .openRouter: preset = ("OpenRouter", "https://openrouter.ai/api/v1", .openAIChat, true)
        case .groq: preset = ("Groq", "https://api.groq.com/openai/v1", .openAIChat, true)
        case .deepSeek: preset = ("DeepSeek", "https://api.deepseek.com/v1", .openAIChat, true)
        case .ollama: preset = ("Ollama", "http://127.0.0.1:11434/v1", .openAIChat, false)
        case .llamaCpp: preset = ("llama.cpp", "http://127.0.0.1:8080/v1", .openAIChat, false)
        case .lmStudio, .vmlx, .builtIn, .custom, .folder: return nil
        }
        guard let url = URL(string: preset.1) else { return nil }
        self.server = server
        name = preset.0
        baseURL = url
        format = preset.2
        isHosted = preset.3
    }

    public static let all: [ModelAPI] = LocalModelChoice.Server.allCases.compactMap(\.api)

    /// The Keychain account the user's key for this service is kept under.
    public var keyAccount: String { "api-key.\(server.rawValue)" }

    public var chatURL: URL {
        baseURL.appending(path: format == .anthropicMessages ? "messages" : "chat/completions")
    }

    public var modelsURL: URL { baseURL.appending(path: "models") }

    /// Where a key can be checked when listing models does not need one: OpenRouter's model list is public, so it
    /// would accept a wrong key.
    public var keyCheckURL: URL? {
        server == .openRouter ? baseURL.appending(path: "key") : nil
    }

    public func headers(apiKey: String?) -> [String: String] {
        var headers = ["Content-Type": "application/json"]
        guard let apiKey, !apiKey.isEmpty else { return headers }
        switch format {
        case .openAIChat:
            headers["Authorization"] = "Bearer \(apiKey)"
        case .anthropicMessages:
            headers["x-api-key"] = apiKey
            headers["anthropic-version"] = Self.anthropicVersion
        }
        return headers
    }

    public func requestBody(model: String, messages: [ChatMessage], temperature: Double, maxTokens: Int, stream: Bool) throws -> Data {
        let encoder = JSONEncoder()
        encoder.outputFormatting = .sortedKeys
        switch format {
        case .anthropicMessages:
            let system = messages.filter { $0.role == .system }.map(\.content).joined(separator: "\n\n")
            let turns = messages.filter { $0.role != .system && !$0.content.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }
            return try encoder.encode(AnthropicBody(
                model: model, system: system.isEmpty ? nil : system,
                messages: turns.map { Turn(role: $0.role.rawValue, content: $0.content) },
                maxTokens: maxTokens, temperature: temperature, stream: stream))
        case .openAIChat:
            // OpenAI's own reasoning models refuse `max_tokens` and any temperature but the default; the services
            // copying the older API still expect both.
            let isOpenAI = server == .openAI
            let takesTemperature = !isOpenAI || Self.temperatureModelPrefixes.contains { model.lowercased().hasPrefix($0) }
            return try encoder.encode(OpenAIBody(
                model: model, messages: messages.map { Turn(role: $0.role.rawValue, content: $0.content) },
                stream: stream,
                temperature: takesTemperature ? temperature : nil,
                maxTokens: isOpenAI ? nil : maxTokens,
                maxCompletionTokens: isOpenAI ? maxTokens + Self.reasoningAllowance : nil))
        }
    }

    /// How much text a reply may have before it is cut, where the token limit sent cannot keep it short; nil where it
    /// can. OpenAI is sent room for reasoning on top of `maxTokens`, which a model that does not reason spends on text.
    public func replyCharacterLimit(maxTokens: Int) -> Int? {
        server == .openAI ? maxTokens * Self.charactersPerToken : nil
    }

    /// The text in one `data:` payload of a streamed reply; nil for events that carry none. Separate reasoning
    /// fields are ignored.
    public func streamedText(in payload: String) throws -> String? {
        guard let object = try? JSONSerialization.jsonObject(with: Data(payload.utf8)) as? [String: Any] else {
            throw ModelAPIError.unexpectedResponse
        }
        if let message = Self.errorMessage(in: object) { throw ModelAPIError.service(message) }
        switch format {
        case .anthropicMessages:
            guard object["type"] as? String == "content_block_delta",
                  let delta = object["delta"] as? [String: Any] else { return nil }
            return delta["text"] as? String
        case .openAIChat:
            let choice = (object["choices"] as? [[String: Any]])?.first
            return (choice?["delta"] as? [String: Any])?["content"] as? String
        }
    }

    /// Model ids from a `GET /models` answer, sorted.
    public static func modelIDs(inListResponse data: Data) throws -> [String] {
        guard let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let models = object["data"] as? [[String: Any]] else { throw ModelAPIError.unexpectedResponse }
        return models.compactMap { $0["id"] as? String }.sorted()
    }

    /// The service's own explanation in an error body, shortened for showing to the user.
    public static func errorMessage(inErrorBody data: Data) -> String? {
        guard let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else { return nil }
        return errorMessage(in: object)
    }

    private static func errorMessage(in object: [String: Any]) -> String? {
        guard let error = object["error"], !(error is NSNull) else { return nil }
        let message = (error as? [String: Any])?["message"] as? String ?? (error as? String) ?? String(describing: error)
        return String(message.prefix(300))
    }
}

private struct Turn: Encodable {
    let role: String
    let content: String
}

private struct OpenAIBody: Encodable {
    let model: String
    let messages: [Turn]
    let stream: Bool
    let temperature: Double?
    let maxTokens: Int?
    let maxCompletionTokens: Int?

    enum CodingKeys: String, CodingKey {
        case model, messages, stream, temperature
        case maxTokens = "max_tokens"
        case maxCompletionTokens = "max_completion_tokens"
    }
}

private struct AnthropicBody: Encodable {
    let model: String
    let system: String?
    let messages: [Turn]
    let maxTokens: Int
    let temperature: Double
    let stream: Bool

    enum CodingKeys: String, CodingKey {
        case model, system, messages, temperature, stream
        case maxTokens = "max_tokens"
    }
}
