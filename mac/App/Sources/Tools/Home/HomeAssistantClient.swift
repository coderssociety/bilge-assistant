import AsistanCore
import Foundation
import Network

enum HomeAssistantError: LocalizedError, Equatable {
    case invalidAddress
    case noToken
    case unreachable
    case timedOut
    case unauthorized
    case badStatus(Int)
    case unexpected

    var errorDescription: String? {
        switch self {
        case .invalidAddress: String(localized: "Home Assistant adresi geçersiz; ayarlarda http:// ya da https:// ile başlayan adresi gir.")
        case .noToken: String(localized: "Home Assistant erişim anahtarı kayıtlı değil; ayarlardan ekleyebilirsin.")
        case .unreachable: String(localized: "Home Assistant'a ulaşamadım; adres doğru mu, Mac aynı ağda mı?")
        case .timedOut: String(localized: "Home Assistant zamanında yanıt vermedi.")
        case .unauthorized: String(localized: "Home Assistant erişim anahtarını kabul etmedi (401); ayarlardan yeni bir uzun ömürlü erişim anahtarı gir.")
        case let .badStatus(status): String(localized: "Home Assistant bir hatayla yanıt verdi (\(status)).")
        case .unexpected: String(localized: "Home Assistant'tan anlayamadığım bir yanıt geldi.")
        }
    }
}

/// Talks to the one Home Assistant address the user typed in Settings. Home Assistant usually lives on the local
/// network, which `WebFetch` refuses on purpose, so this separate client exists: it connects only to that address,
/// sends the token only there, follows no redirects and bypasses system proxies, so the token cannot end up anywhere
/// else.
enum HomeAssistantClient {
    struct Connection: Sendable {
        let base: URL
        let token: String
    }

    private static let timeout: Duration = .seconds(15)
    private static let maxBodyBytes = 1_000_000
    private static let headerAllowance = 64 * 1024

    /// What Home Assistant says back to the command; nil when it says nothing.
    static func process(_ text: String, language: AssistantLanguage, on connection: Connection) async throws -> String? {
        let request = HomeAssistantAPI.conversationRequest(text, language: language, base: connection.base, token: connection.token)
        let response = try await send(request, to: connection.base)
        do {
            return try HomeAssistantAPI.spokenReply(from: response.body)
        } catch {
            throw HomeAssistantError.unexpected
        }
    }

    /// Throws unless the address answers and accepts the token.
    static func check(_ connection: Connection) async throws {
        _ = try await send(HomeAssistantAPI.statusRequest(base: connection.base, token: connection.token), to: connection.base)
    }

    private static func send(_ request: Data, to base: URL) async throws -> HTTPResponse {
        let isSecure = base.scheme?.lowercased() == "https"
        guard let host = base.host(), let number = UInt16(exactly: base.port ?? (isSecure ? 443 : 80)),
              let port = NWEndpoint.Port(rawValue: number) else {
            throw HomeAssistantError.invalidAddress
        }
        let parameters: NWParameters = isSecure ? .tls : .tcp
        parameters.preferNoProxies = true
        let connection = NWConnection(host: NWEndpoint.Host(host), port: port, using: parameters)
        defer { connection.cancel() }
        let response: HTTPResponse
        do {
            response = try await withThrowingTaskGroup(of: HTTPResponse.self) { group in
                group.addTask {
                    try await withTaskCancellationHandler {
                        try await PublicHTTPClient.ready(connection)
                        try await PublicHTTPClient.send(request, on: connection)
                        let (data, _) = try await PublicHTTPClient.receiveAll(connection, limit: maxBodyBytes + headerAllowance)
                        return try HTTPResponse.parse(data)
                    } onCancel: {
                        connection.cancel()
                    }
                }
                group.addTask {
                    try await Task.sleep(for: timeout)
                    throw HomeAssistantError.timedOut
                }
                defer { group.cancelAll() }
                guard let response = try await group.next() else { throw CancellationError() }
                return response
            }
        } catch let error as HomeAssistantError {
            throw error
        } catch is CancellationError {
            throw CancellationError()
        } catch is HTTPResponseError, WebFetchError.tooLarge {
            throw HomeAssistantError.unexpected
        } catch {
            Log.tools.error("Home Assistant unreachable: \(String(describing: error), privacy: .public)")
            throw HomeAssistantError.unreachable
        }
        return try checked(response)
    }

    private static func checked(_ response: HTTPResponse) throws -> HTTPResponse {
        switch response.status {
        case 200..<300:
            guard response.body.count <= maxBodyBytes else { throw HomeAssistantError.unexpected }
            return response
        case 401, 403:
            throw HomeAssistantError.unauthorized
        case 300..<400:
            // Not followed: the token would go along to another address.
            throw HomeAssistantError.unexpected
        default:
            throw HomeAssistantError.badStatus(response.status)
        }
    }
}
