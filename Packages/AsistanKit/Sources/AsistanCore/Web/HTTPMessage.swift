import Foundation

/// A minimal HTTP/1.1 GET over a connection the caller opened, so the caller can check which address
/// it actually reached before anything is sent. It asks for an uncompressed body and a closed
/// connection, which keeps the response simple: read until the server closes, then parse.
public enum HTTPRequest {
    public static func get(_ url: URL, headers: [(String, String)]) -> Data {
        var target = url.path(percentEncoded: true)
        if target.isEmpty { target = "/" }
        if let query = url.query(percentEncoded: true) { target += "?\(query)" }
        var host = url.host(percentEncoded: true) ?? ""
        if host.contains(":") { host = "[\(host)]" }
        if let port = url.port { host += ":\(port)" }
        let fields = [("Host", host)] + headers + [("Accept-Encoding", "identity"), ("Connection", "close")]
        let lines = fields
            .filter { name, value in !(name + value).contains(where: \.isNewline) }
            .map { "\($0): \($1)" }
        return Data((["GET \(target) HTTP/1.1"] + lines).joined(separator: "\r\n").utf8 + Data("\r\n\r\n".utf8))
    }
}

public enum HTTPResponseError: Error, Equatable {
    case malformed
    case unsupportedEncoding
}

public struct HTTPResponse: Sendable {
    public let status: Int
    public let headers: [(name: String, value: String)]
    public let body: Data

    private static let separator = Data("\r\n\r\n".utf8)
    private static let redirectStatuses: Set<Int> = [301, 302, 303, 307, 308]

    public func header(_ name: String) -> String? {
        headers.first { $0.name.caseInsensitiveCompare(name) == .orderedSame }?.value
    }

    public func redirectTarget(from url: URL) -> URL? {
        guard Self.redirectStatuses.contains(status), let location = header("Location") else { return nil }
        return URL(string: location, relativeTo: url)?.absoluteURL
    }

    /// Whether `data` already holds the whole response, so reading can stop even if the server keeps
    /// the connection open despite "Connection: close". Without a length or chunking, only the close tells.
    public static func isComplete(_ data: Data) -> Bool {
        guard let split = data.firstRange(of: separator) else { return false }
        let head = String(decoding: data[data.startIndex..<split.lowerBound], as: UTF8.self).lowercased()
        let bodyCount = data.distance(from: split.upperBound, to: data.endIndex)
        if head.contains("transfer-encoding: chunked") {
            return data.suffix(5) == Data("0\r\n\r\n".utf8)
        }
        for line in head.components(separatedBy: "\r\n") where line.hasPrefix("content-length:") {
            guard let length = Int(line.dropFirst("content-length:".count).trimmingCharacters(in: .whitespaces)) else { return false }
            return bodyCount >= length
        }
        return false
    }

    /// Parses a complete response: everything the server sent before closing the connection.
    public static func parse(_ data: Data) throws -> HTTPResponse {
        guard let split = data.firstRange(of: separator) else { throw HTTPResponseError.malformed }
        let head = String(decoding: data[data.startIndex..<split.lowerBound], as: UTF8.self)
        let lines = head.components(separatedBy: "\r\n")
        let statusParts = lines[0].split(separator: " ", maxSplits: 2)
        guard statusParts.count >= 2, statusParts[0].hasPrefix("HTTP/"), let status = Int(statusParts[1]) else {
            throw HTTPResponseError.malformed
        }
        let headers = lines.dropFirst().compactMap { line -> (name: String, value: String)? in
            guard let colon = line.firstIndex(of: ":") else { return nil }
            return (String(line[..<colon]), line[line.index(after: colon)...].trimmingCharacters(in: .whitespaces))
        }
        let response = HTTPResponse(status: status, headers: headers, body: Data())
        if let encoding = response.header("Content-Encoding"), encoding.lowercased() != "identity" {
            throw HTTPResponseError.unsupportedEncoding
        }
        let rest = Data(data[split.upperBound...])
        let body: Data
        if response.header("Transfer-Encoding")?.lowercased().contains("chunked") == true {
            body = try dechunked(rest)
        } else if let length = response.header("Content-Length").flatMap(Int.init), length >= 0 {
            // A body cut short would otherwise pass as the whole page.
            guard rest.count >= length else { throw HTTPResponseError.malformed }
            body = rest.prefix(length)
        } else {
            body = rest
        }
        return HTTPResponse(status: status, headers: headers, body: body)
    }

    private static func dechunked(_ data: Data) throws -> Data {
        let lineEnd = Data("\r\n".utf8)
        var body = Data()
        var index = data.startIndex
        while true {
            guard let end = data[index...].firstRange(of: lineEnd) else { throw HTTPResponseError.malformed }
            let sizeText = String(decoding: data[index..<end.lowerBound], as: UTF8.self)
                .split(separator: ";").first.map { $0.trimmingCharacters(in: .whitespaces) } ?? ""
            guard let size = Int(sizeText, radix: 16), size >= 0 else { throw HTTPResponseError.malformed }
            if size == 0 { return body }
            let start = end.upperBound
            // Compared without adding to `size`: a hostile "7FFFFFFFFFFFFFFF" would overflow.
            guard size <= data.distance(from: start, to: data.endIndex) - lineEnd.count else { throw HTTPResponseError.malformed }
            let stop = data.index(start, offsetBy: size)
            body.append(data[start..<stop])
            index = data.index(stop, offsetBy: lineEnd.count)
        }
    }
}
