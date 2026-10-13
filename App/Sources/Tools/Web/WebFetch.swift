import AsistanCore
import Foundation

enum WebFetchError: LocalizedError {
    case badStatus(Int)
    case tooLarge
    case unsupportedAddress
    case localAddress

    var errorDescription: String? {
        switch self {
        case let .badStatus(status): "Sunucu yanıt vermedi (\(status))."
        case .tooLarge: "Sayfa okunamayacak kadar büyük."
        case .unsupportedAddress: "Bu adresi açamam."
        case .localAddress: "Güvenlik için yerel ağdaki ya da bu Mac'teki adresleri okumuyorum."
        }
    }
}

/// The only way tools reach the internet: GET requests over http(s) to public addresses, bounded in
/// time and size. The language models never get network access; tools fetch data and the models
/// only read it. Every redirect is checked again, so a public page cannot bounce a request into the
/// local network. (A host that re-resolves to a private address between the check and the request
/// is not caught; the window is the length of one DNS lookup.)
enum WebFetch {
    private static let requestTimeout: TimeInterval = 10
    private static let resourceTimeout: TimeInterval = 20
    private static let maxBytes = 3_000_000
    private static let allowedPorts: Set<Int> = [80, 443]

    private static let session: URLSession = {
        let configuration = URLSessionConfiguration.ephemeral
        configuration.timeoutIntervalForRequest = requestTimeout
        configuration.timeoutIntervalForResource = resourceTimeout
        configuration.httpAdditionalHeaders = ["User-Agent": "Mozilla/5.0 (Macintosh) Bilge/0.1", "Accept-Language": "tr,en;q=0.8"]
        return URLSession(configuration: configuration, delegate: RedirectGuard(), delegateQueue: nil)
    }()

    private static let transientStatuses: Set<Int> = [502, 503, 504]
    private static let retryDelay: Duration = .milliseconds(400)

    /// One retry for a gateway hiccup: Open-Meteo answered 503 once and fine right after.
    static func data(from url: URL) async throws -> Data {
        do {
            return try await fetch(url)
        } catch let WebFetchError.badStatus(status) where transientStatuses.contains(status) {
            try await Task.sleep(for: retryDelay)
            return try await fetch(url)
        }
    }

    private static func fetch(_ url: URL) async throws -> Data {
        try validate(url)
        let (bytes, response) = try await session.bytes(from: url)
        if let status = (response as? HTTPURLResponse)?.statusCode, !(200..<300).contains(status) {
            throw WebFetchError.badStatus(status)
        }
        if response.expectedContentLength > maxBytes { throw WebFetchError.tooLarge }
        var data = Data()
        for try await byte in bytes {
            data.append(byte)
            if data.count > maxBytes { throw WebFetchError.tooLarge }
        }
        return data
    }

    static func json<T: Decodable>(_ type: T.Type, from url: URL) async throws -> T {
        try JSONDecoder().decode(type, from: try await data(from: url))
    }

    static func text(from url: URL) async throws -> String {
        let data = try await data(from: url)
        return String(data: data, encoding: .utf8) ?? String(decoding: data, as: UTF8.self)
    }

    /// Scheme, port and every address the host resolves to must be public.
    static func validate(_ url: URL) throws {
        guard ["http", "https"].contains(url.scheme?.lowercased() ?? ""), let host = url.host(), !host.isEmpty else {
            throw WebFetchError.unsupportedAddress
        }
        if let port = url.port, !allowedPorts.contains(port) { throw WebFetchError.unsupportedAddress }
        let bare = host.trimmingCharacters(in: CharacterSet(charactersIn: "[]"))
        let isIPLiteral = bare.contains(":") || Int(bare.split(separator: ".").last ?? "") != nil
        if !isIPLiteral, NetworkAddress.isLocalName(bare) { throw WebFetchError.localAddress }
        let addresses = resolve(bare)
        guard !addresses.isEmpty, addresses.allSatisfy(NetworkAddress.isPublic) else { throw WebFetchError.localAddress }
    }

    private static func resolve(_ host: String) -> [String] {
        var hints = addrinfo(ai_flags: 0, ai_family: AF_UNSPEC, ai_socktype: SOCK_STREAM, ai_protocol: 0,
                             ai_addrlen: 0, ai_canonname: nil, ai_addr: nil, ai_next: nil)
        var list: UnsafeMutablePointer<addrinfo>?
        guard getaddrinfo(host, nil, &hints, &list) == 0, let first = list else { return [] }
        defer { freeaddrinfo(list) }
        return sequence(first: first, next: { $0.pointee.ai_next }).compactMap { entry in
            var buffer = [CChar](repeating: 0, count: Int(NI_MAXHOST))
            guard getnameinfo(entry.pointee.ai_addr, entry.pointee.ai_addrlen, &buffer, socklen_t(buffer.count), nil, 0, NI_NUMERICHOST) == 0
            else { return nil }
            return String(decoding: buffer.prefix { $0 != 0 }.map(UInt8.init), as: UTF8.self)
        }
    }

    private final class RedirectGuard: NSObject, URLSessionTaskDelegate, Sendable {
        func urlSession(_ session: URLSession, task: URLSessionTask, willPerformHTTPRedirection response: HTTPURLResponse,
                        newRequest request: URLRequest) async -> URLRequest? {
            guard let url = request.url, (try? WebFetch.validate(url)) != nil else {
                Log.tools.error("Blocked a redirect to a non-public address")
                return nil
            }
            return request
        }
    }
}
