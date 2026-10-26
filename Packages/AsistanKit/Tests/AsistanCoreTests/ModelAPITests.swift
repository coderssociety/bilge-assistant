import Foundation
import Testing
@testable import AsistanCore

@Suite("ModelAPI")
struct ModelAPITests {
    private let messages: [ChatMessage] = [.system("Kısa cevap ver."), .user("Merhaba"), .assistant(""), .user("Nasılsın?")]

    private func json(_ data: Data) throws -> [String: Any] {
        try #require(try JSONSerialization.jsonObject(with: data) as? [String: Any])
    }

    @Test("every API server has a preset, the servers Bilge runs itself have none")
    func presets() {
        #expect(ModelAPI.all.map(\.server) == [.openAI, .anthropic, .gemini, .openRouter, .groq, .deepSeek, .ollama, .llamaCpp])
        #expect(LocalModelChoice.Server.lmStudio.api == nil)
        #expect(LocalModelChoice.Server.builtIn.api == nil)
        #expect(ModelAPI.all.filter { !$0.isHosted }.map(\.server) == [.ollama, .llamaCpp])
    }

    @Test("servers on this Mac are only reached on the loopback address")
    func localServersAreLoopback() {
        for api in ModelAPI.all where !api.isHosted {
            #expect(api.baseURL.host() == "127.0.0.1")
        }
        for api in ModelAPI.all where api.isHosted {
            #expect(api.baseURL.scheme == "https")
        }
    }

    @Test("an API choice round-trips through its storage key, also with a slash in the model id")
    func storageKey() {
        let choice = LocalModelChoice(server: .openRouter, modelID: "anthropic/claude-sonnet-4.5")
        #expect(LocalModelChoice(storageKey: choice.storageKey) == choice)
        #expect(choice.storageKey == "openrouter:anthropic/claude-sonnet-4.5")
    }

    @Test("OpenAI-style services get a bearer key, Anthropic its own headers, local servers none")
    func headers() throws {
        let openAI = try #require(LocalModelChoice.Server.groq.api)
        #expect(openAI.headers(apiKey: "k")["Authorization"] == "Bearer k")
        let anthropic = try #require(LocalModelChoice.Server.anthropic.api)
        #expect(anthropic.headers(apiKey: "k")["x-api-key"] == "k")
        #expect(anthropic.headers(apiKey: "k")["anthropic-version"] == ModelAPI.anthropicVersion)
        #expect(anthropic.headers(apiKey: "k")["Authorization"] == nil)
        let ollama = try #require(LocalModelChoice.Server.ollama.api)
        #expect(ollama.headers(apiKey: nil).keys.sorted() == ["Content-Type"])
    }

    @Test("endpoints follow each format")
    func urls() throws {
        let anthropic = try #require(LocalModelChoice.Server.anthropic.api)
        #expect(anthropic.chatURL.absoluteString == "https://api.anthropic.com/v1/messages")
        let gemini = try #require(LocalModelChoice.Server.gemini.api)
        #expect(gemini.chatURL.absoluteString == "https://generativelanguage.googleapis.com/v1beta/openai/chat/completions")
        #expect(gemini.modelsURL.absoluteString == "https://generativelanguage.googleapis.com/v1beta/openai/models")
    }

    @Test("an OpenAI-compatible body keeps the messages and sends temperature and max_tokens")
    func openAICompatibleBody() throws {
        let api = try #require(LocalModelChoice.Server.deepSeek.api)
        let body = try json(api.requestBody(model: "deepseek-chat", messages: messages, temperature: 0.6, maxTokens: 250, stream: true))
        #expect(body["model"] as? String == "deepseek-chat")
        #expect(body["stream"] as? Bool == true)
        #expect(body["temperature"] as? Double == 0.6)
        #expect(body["max_tokens"] as? Int == 250)
        #expect(body["max_completion_tokens"] == nil)
        let sent = try #require(body["messages"] as? [[String: String]])
        #expect(sent.first == ["role": "system", "content": "Kısa cevap ver."])
        #expect(sent.count == 4)
    }

    @Test("OpenAI itself gets max_completion_tokens with room for reasoning, and no temperature")
    func openAIBody() throws {
        let api = try #require(LocalModelChoice.Server.openAI.api)
        let body = try json(api.requestBody(model: "gpt-5", messages: messages, temperature: 0.6, maxTokens: 250, stream: false))
        #expect(body["temperature"] == nil)
        #expect(body["max_tokens"] == nil)
        #expect(body["max_completion_tokens"] as? Int == 250 + ModelAPI.reasoningAllowance)
    }

    @Test("OpenAI's older chat models keep their temperature, reasoning models get none")
    func openAITemperature() throws {
        let api = try #require(LocalModelChoice.Server.openAI.api)
        let older = try json(api.requestBody(model: "gpt-4.1-mini", messages: messages, temperature: 0, maxTokens: 250, stream: true))
        #expect(older["temperature"] as? Double == 0)
        let reasoning = try json(api.requestBody(model: "o4-mini", messages: messages, temperature: 0, maxTokens: 250, stream: true))
        #expect(reasoning["temperature"] == nil)
    }

    @Test("only OpenAI's reply is cut by length, since only it gets room for reasoning")
    func replyLimit() throws {
        #expect(try #require(LocalModelChoice.Server.openAI.api).replyCharacterLimit(maxTokens: 250) == 1000)
        #expect(try #require(LocalModelChoice.Server.anthropic.api).replyCharacterLimit(maxTokens: 250) == nil)
    }

    @Test("an OpenRouter key is checked where a wrong one is refused; the others by their model list")
    func keyCheck() throws {
        #expect(try #require(LocalModelChoice.Server.openRouter.api).keyCheckURL?.absoluteString == "https://openrouter.ai/api/v1/key")
        #expect(try #require(LocalModelChoice.Server.groq.api).keyCheckURL == nil)
    }

    @Test("Anthropic gets the system text apart and no empty turns")
    func anthropicBody() throws {
        let api = try #require(LocalModelChoice.Server.anthropic.api)
        let body = try json(api.requestBody(model: "claude-haiku-4-5", messages: messages, temperature: 0.3, maxTokens: 250, stream: true))
        #expect(body["system"] as? String == "Kısa cevap ver.")
        #expect(body["max_tokens"] as? Int == 250)
        let sent = try #require(body["messages"] as? [[String: String]])
        #expect(sent == [["role": "user", "content": "Merhaba"], ["role": "user", "content": "Nasılsın?"]])
    }

    @Test("streamed text is read from each format and other events carry none")
    func streamedText() throws {
        let openAI = try #require(LocalModelChoice.Server.openAI.api)
        #expect(try openAI.streamedText(in: #"{"choices":[{"delta":{"content":"Mer"}}]}"#) == "Mer")
        #expect(try openAI.streamedText(in: #"{"choices":[{"delta":{"reasoning_content":"hmm"}}]}"#) == nil)
        #expect(try openAI.streamedText(in: #"{"choices":[],"error":null}"#) == nil)
        let anthropic = try #require(LocalModelChoice.Server.anthropic.api)
        #expect(try anthropic.streamedText(in: #"{"type":"content_block_delta","index":0,"delta":{"type":"text_delta","text":"haba"}}"#) == "haba")
        #expect(try anthropic.streamedText(in: #"{"type":"message_start","message":{}}"#) == nil)
    }

    @Test("an error inside a stream is reported with the service's words")
    func streamedError() throws {
        let anthropic = try #require(LocalModelChoice.Server.anthropic.api)
        #expect(throws: ModelAPIError.service("Overloaded")) {
            try anthropic.streamedText(in: #"{"type":"error","error":{"type":"overloaded_error","message":"Overloaded"}}"#)
        }
        #expect(throws: ModelAPIError.unexpectedResponse) { try anthropic.streamedText(in: "not json") }
    }

    @Test("model lists and error bodies are read")
    func lists() throws {
        let ids = try ModelAPI.modelIDs(inListResponse: Data(#"{"object":"list","data":[{"id":"b"},{"id":"a"},{"x":1}]}"#.utf8))
        #expect(ids == ["a", "b"])
        #expect(throws: ModelAPIError.unexpectedResponse) { try ModelAPI.modelIDs(inListResponse: Data("[]".utf8)) }
        #expect(ModelAPI.errorMessage(inErrorBody: Data(#"{"error":{"message":"Incorrect API key"}}"#.utf8)) == "Incorrect API key")
        #expect(ModelAPI.errorMessage(inErrorBody: Data("<html>".utf8)) == nil)
    }

    @Test("each service keeps its key under its own account")
    func keyAccounts() {
        #expect(Set(ModelAPI.all.map(\.keyAccount)).count == ModelAPI.all.count)
    }
}
