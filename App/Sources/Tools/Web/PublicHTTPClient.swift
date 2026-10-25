import AsistanCore
import Foundation
import Network
import Synchronization

/// Opens the connection itself and checks the address it actually reached before anything is sent.
/// Validating a host name and then letting URLSession resolve it again left a gap: the name could
/// re-resolve to a local address in between (DNS rebinding). Here there is only one resolution, and
/// the request goes out only after the connected peer is known to be public.
enum PublicHTTPClient {
    private static let queue = DispatchQueue(label: "Bilge.PublicHTTPClient")
    private static let receiveChunk = 64 * 1024
    private static let headerAllowance = 64 * 1024

    /// With `truncating`, a body longer than `maxBodyBytes` is cut there instead of refused.
    static func get(_ url: URL, headers: [(String, String)], maxBodyBytes: Int, truncating: Bool = false,
                    timeout: Duration) async throws -> HTTPResponse {
        try await exchange(HTTPRequest.get(url, headers: headers), with: url, maxBodyBytes: maxBodyBytes, truncating: truncating,
                           timeout: timeout)
    }

    static func post(_ url: URL, headers: [(String, String)], body: Data, maxBodyBytes: Int,
                     timeout: Duration) async throws -> HTTPResponse {
        try await exchange(HTTPRequest.post(url, headers: headers, body: body), with: url, maxBodyBytes: maxBodyBytes,
                           truncating: false, timeout: timeout)
    }

    private static func exchange(_ request: Data, with url: URL, maxBodyBytes: Int, truncating: Bool,
                                 timeout: Duration) async throws -> HTTPResponse {
        let isSecure = url.scheme?.lowercased() == "https"
        guard let host = url.host(), let number = UInt16(exactly: url.port ?? (isSecure ? 443 : 80)),
              let port = NWEndpoint.Port(rawValue: number) else {
            throw WebFetchError.unsupportedAddress
        }
        let parameters: NWParameters = isSecure ? .tls : .tcp
        // A system proxy would make the proxy the peer, and the check below would refuse everything.
        parameters.preferNoProxies = true
        let connection = NWConnection(host: NWEndpoint.Host(host), port: port, using: parameters)
        defer { connection.cancel() }

        return try await withThrowingTaskGroup(of: HTTPResponse.self) { group in
            group.addTask {
                try await withTaskCancellationHandler {
                    try await ready(connection)
                    try requirePublicPeer(connection)
                    try await send(request, on: connection)
                    let (data, truncated) = try await receiveAll(connection, limit: maxBodyBytes + headerAllowance,
                                                                 truncating: truncating)
                    return try HTTPResponse.parse(data, truncated: truncated)
                } onCancel: {
                    connection.cancel()
                }
            }
            group.addTask {
                try await Task.sleep(for: timeout)
                throw WebFetchError.timedOut
            }
            defer { group.cancelAll() }
            guard let response = try await group.next() else { throw CancellationError() }
            return response
        }
    }

    private static func ready(_ connection: NWConnection) async throws {
        let once = Once()
        try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, any Error>) in
            connection.stateUpdateHandler = { state in
                switch state {
                case .ready: once.run { continuation.resume() }
                case let .failed(error), let .waiting(error): once.run { continuation.resume(throwing: error) }
                case .cancelled: once.run { continuation.resume(throwing: CancellationError()) }
                default: break
                }
            }
            connection.start(queue: queue)
        }
    }

    private static func requirePublicPeer(_ connection: NWConnection) throws {
        guard case let .hostPort(host, _)? = connection.currentPath?.remoteEndpoint else {
            throw WebFetchError.localAddress
        }
        let address: String
        switch host {
        case let .ipv4(ip): address = "\(ip)"
        case let .ipv6(ip): address = "\(ip)"
        default: throw WebFetchError.localAddress
        }
        let bare = String(address.split(separator: "%").first ?? "")
        guard NetworkAddress.isPublic(bare) else {
            Log.tools.error("Refused a connection that reached a non-public address")
            throw WebFetchError.localAddress
        }
    }

    private static func send(_ data: Data, on connection: NWConnection) async throws {
        try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, any Error>) in
            connection.send(content: data, completion: .contentProcessed { error in
                if let error { continuation.resume(throwing: error) } else { continuation.resume() }
            })
        }
    }

    /// Until the server closes the connection (the request asked it to), or until the response is
    /// complete for a server that keeps it open anyway.
    private static func receiveAll(_ connection: NWConnection, limit: Int, truncating: Bool) async throws -> (Data, Bool) {
        var data = Data()
        while true {
            let (chunk, isComplete) = try await receive(connection)
            if let chunk { data.append(chunk) }
            if data.count > limit {
                guard truncating else { throw WebFetchError.tooLarge }
                return (data.prefix(limit), true)
            }
            if isComplete || HTTPResponse.isComplete(data) { return (data, false) }
        }
    }

    private static func receive(_ connection: NWConnection) async throws -> (Data?, Bool) {
        try await withCheckedThrowingContinuation { continuation in
            connection.receive(minimumIncompleteLength: 1, maximumLength: receiveChunk) { content, _, isComplete, error in
                if let error { continuation.resume(throwing: error) } else { continuation.resume(returning: (content, isComplete)) }
            }
        }
    }

    /// NWConnection reports states after the one we wait for; the continuation may resume only once.
    private final class Once: Sendable {
        private let done = Mutex(false)

        func run(_ body: () -> Void) {
            let first = done.withLock { done in
                defer { done = true }
                return !done
            }
            if first { body() }
        }
    }
}
