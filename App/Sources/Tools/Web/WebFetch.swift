import AsistanCore
import Foundation

enum WebFetchError: LocalizedError {
    case badStatus(Int)
    case tooLarge
    case unsupportedAddress
    case localAddress
    case timedOut
    case tooManyRedirects
    case unreachable
    case unreadable

    var errorDescription: String? {
        switch self {
        case let .badStatus(status): "Sunucu yanıt vermedi (\(status))."
        case .tooLarge: "Sayfa okunamayacak kadar büyük."
        case .unsupportedAddress: "Bu adresi açamam."
        case .localAddress: "Güvenlik için yerel ağdaki ya da bu Mac'teki adresleri okumuyorum."
        case .timedOut: "Site zamanında yanıt vermedi."
        case .tooManyRedirects: "Site beni sürekli başka adrese yönlendiriyor."
        case .unreachable: "Siteye bağlanamadım. İnternet bağlantını kontrol eder misin?"
        case .unreadable: "Sitenin gönderdiği yanıtı okuyamadım."
        }
    }
}

/// The only way tools reach the internet: GET requests over http(s) to public addresses, bounded in
/// time and size. The language models never get network access; tools fetch data and the models
/// only read it. Every hop of a redirect is checked again, and each connection is checked at the
/// address it actually reached (see `PublicHTTPClient`).
enum WebFetch {
    private static let timeout: Duration = .seconds(15)
    /// For the whole fetch, redirects included; otherwise five slow hops could take over a minute.
    private static let totalTimeout: Duration = .seconds(25)
    private static let maxBytes = 3_000_000
    private static let maxRedirects = 5
    private static let allowedPorts: Set<Int> = [80, 443]
    private static let headers = [("User-Agent", "Mozilla/5.0 (Macintosh) Bilge/0.1"), ("Accept-Language", "tr,en;q=0.8")]

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

    static func json<T: Decodable>(_ type: T.Type, from url: URL) async throws -> T {
        try JSONDecoder().decode(type, from: try await data(from: url))
    }

    static func text(from url: URL) async throws -> String {
        let data = try await data(from: url)
        return String(data: data, encoding: .utf8) ?? String(decoding: data, as: UTF8.self)
    }

    private static func fetch(_ url: URL) async throws -> Data {
        var current = url
        let deadline = ContinuousClock.now + totalTimeout
        for _ in 0...maxRedirects {
            try validate(current)
            let remaining = deadline - ContinuousClock.now
            guard remaining > .zero else { throw WebFetchError.timedOut }
            let response = try await get(current, timeout: min(timeout, remaining))
            if let next = response.redirectTarget(from: current) {
                current = next
                continue
            }
            guard (200..<300).contains(response.status) else { throw WebFetchError.badStatus(response.status) }
            guard response.body.count <= maxBytes else { throw WebFetchError.tooLarge }
            return response.body
        }
        throw WebFetchError.tooManyRedirects
    }

    private static func get(_ url: URL, timeout: Duration) async throws -> HTTPResponse {
        do {
            return try await PublicHTTPClient.get(url, headers: headers, maxBodyBytes: maxBytes, timeout: timeout)
        } catch let error as WebFetchError {
            throw error
        } catch let error as HTTPResponseError {
            Log.tools.error("Unreadable response: \(String(describing: error), privacy: .public)")
            throw WebFetchError.unreadable
        } catch is CancellationError {
            throw CancellationError()
        } catch {
            Log.tools.error("Fetch failed: \(String(describing: error), privacy: .public)")
            throw WebFetchError.unreachable
        }
    }

    /// Scheme, port and the obvious local names; the connected address is checked when connecting.
    static func validate(_ url: URL) throws {
        guard ["http", "https"].contains(url.scheme?.lowercased() ?? ""), let host = url.host(), !host.isEmpty else {
            throw WebFetchError.unsupportedAddress
        }
        if let port = url.port, !allowedPorts.contains(port) { throw WebFetchError.unsupportedAddress }
        let bare = host.trimmingCharacters(in: CharacterSet(charactersIn: "[]"))
        let isIPLiteral = bare.contains(":") || Int(bare.split(separator: ".").last ?? "") != nil
        if isIPLiteral ? !NetworkAddress.isPublic(bare) : NetworkAddress.isLocalName(bare) {
            throw WebFetchError.localAddress
        }
    }
}
