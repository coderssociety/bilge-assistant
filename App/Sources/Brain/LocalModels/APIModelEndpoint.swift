import AsistanCore
import Foundation

enum APIModelError: LocalizedError {
    case noKey(String)
    case rejectedKey(String)
    case refused(String, Int, String?)

    var errorDescription: String? {
        switch self {
        case let .noKey(service): String(localized: "\(service) için API anahtarı kayıtlı değil.")
        case let .rejectedKey(service): String(localized: "\(service) API anahtarını kabul etmedi.")
        case let .refused(service, status, message):
            String(localized: "\(service) bir hatayla yanıt verdi (\(status))") + (message.map { ": \($0)" } ?? ".")
        }
    }
}

/// A conversation model behind an HTTP API: a hosted service with the user's key, or Ollama or llama.cpp on this Mac.
/// Like the other conversation models it only produces text; tools stay with Apple's model.
struct APIModelEndpoint: LoadedChatModel {
    let api: ModelAPI
    let modelID: String
    let apiKey: String?

    /// How long a silent connection is waited on before Apple's model answers instead.
    private static let requestTimeout: TimeInterval = 30
    private static let errorBodyLimit = 4096
    private static var session: URLSession { APISession.shared }

    /// The user's key from the Keychain; throws when a hosted service has none.
    static func connect(_ choice: LocalModelChoice) throws -> APIModelEndpoint {
        guard let api = choice.server.api else { throw LocalModelServerError.loadFailed(choice.modelID) }
        return APIModelEndpoint(api: api, modelID: choice.modelID, apiKey: try key(for: api))
    }

    static func key(for api: ModelAPI) throws -> String? {
        guard api.isHosted else { return nil }
        guard let key = try Keychain.read(api.keyAccount), !key.isEmpty else { throw APIModelError.noKey(api.name) }
        return key
    }

    /// The models the service offers to this key; also how settings check a key.
    static func models(of api: ModelAPI, apiKey: String?) async throws -> [String] {
        if let keyCheck = api.keyCheckURL {
            let (data, response) = try await session.data(for: getRequest(keyCheck, api: api, apiKey: apiKey))
            try check(response, body: data, api: api)
        }
        let (data, response) = try await session.data(for: getRequest(api.modelsURL, api: api, apiKey: apiKey))
        try check(response, body: data, api: api)
        return try ModelAPI.modelIDs(inListResponse: data)
    }

    private static func getRequest(_ url: URL, api: ModelAPI, apiKey: String?) -> URLRequest {
        var request = URLRequest(url: url, timeoutInterval: 20)
        for (field, value) in api.headers(apiKey: apiKey) { request.setValue(value, forHTTPHeaderField: field) }
        return request
    }

    func streamReply(messages: [ChatMessage], temperature: Double, maxTokens: Int) -> AsyncThrowingStream<String, any Error> {
        AsyncThrowingStream { continuation in
            let task = Task {
                do {
                    let request = try makeRequest(messages: messages, temperature: temperature, maxTokens: maxTokens, stream: true)
                    let (bytes, response) = try await Self.session.bytes(for: request)
                    if let status = (response as? HTTPURLResponse)?.statusCode, !(200..<300).contains(status) {
                        var body = Data()
                        for try await byte in bytes where body.count < Self.errorBodyLimit { body.append(byte) }
                        try Self.check(response, body: body, api: api)
                    }
                    let limit = api.replyCharacterLimit(maxTokens: maxTokens)
                    var length = 0
                    for try await line in bytes.lines {
                        switch ServerSentEventLine(line) {
                        case .ignored: continue
                        case .done: continuation.finish(); return
                        case let .data(payload):
                            guard let text = try api.streamedText(in: payload), !text.isEmpty else { continue }
                            continuation.yield(text)
                            length += text.count
                            if let limit, length >= limit { continuation.finish(); return }
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

    /// A hosted service has nothing to load and every request is billed, so only a server on this Mac is warmed up:
    /// Ollama and llama.cpp load the model with the first request.
    func warmUp(instructions: String) async throws {
        guard !api.isHosted else { return }
        let request = try makeRequest(messages: [.system(instructions), .user("Merhaba")], temperature: 0, maxTokens: 1, stream: false)
        let (data, response) = try await Self.session.data(for: request)
        try Self.check(response, body: data, api: api)
    }

    private func makeRequest(messages: [ChatMessage], temperature: Double, maxTokens: Int, stream: Bool) throws -> URLRequest {
        var request = URLRequest(url: api.chatURL, timeoutInterval: Self.requestTimeout)
        request.httpMethod = "POST"
        for (field, value) in api.headers(apiKey: apiKey) { request.setValue(value, forHTTPHeaderField: field) }
        request.httpBody = try api.requestBody(model: modelID, messages: messages, temperature: temperature,
                                               maxTokens: maxTokens, stream: stream)
        return request
    }

    static func check(_ response: URLResponse, body: Data, api: ModelAPI) throws {
        guard let status = (response as? HTTPURLResponse)?.statusCode, !(200..<300).contains(status) else { return }
        if status == 401 || status == 403 { throw APIModelError.rejectedKey(api.name) }
        throw APIModelError.refused(api.name, status, ModelAPI.errorMessage(inErrorBody: body))
    }
}

/// For every request that carries a key in a header: a redirect must not carry it to another address.
enum APISession {
    static let shared = URLSession(configuration: .ephemeral, delegate: RedirectRefuser(), delegateQueue: nil)
}

private final class RedirectRefuser: NSObject, URLSessionTaskDelegate {
    func urlSession(_ session: URLSession, task: URLSessionTask, willPerformHTTPRedirection response: HTTPURLResponse,
                    newRequest request: URLRequest) async -> URLRequest? {
        nil
    }
}
