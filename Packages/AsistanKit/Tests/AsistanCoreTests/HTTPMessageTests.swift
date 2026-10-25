import Foundation
import Testing
@testable import AsistanCore

@Suite("HTTPMessage")
struct HTTPMessageTests {
    private func raw(_ text: String) -> Data { Data(text.utf8) }

    @Test("renders a GET request with host, query and closing connection")
    func request() throws {
        let url = try #require(URL(string: "https://example.com/a/b?q=%C3%A7ay&x=1"))
        let text = String(decoding: HTTPRequest.get(url, headers: [("User-Agent", "Bilge")]), as: UTF8.self)
        #expect(text.hasPrefix("GET /a/b?q=%C3%A7ay&x=1 HTTP/1.1\r\nHost: example.com\r\n"))
        #expect(text.contains("User-Agent: Bilge\r\n"))
        #expect(text.contains("Accept-Encoding: identity\r\n"))
        #expect(text.hasSuffix("Connection: close\r\n\r\n"))
    }

    @Test("keeps a non-default port in the Host header and uses / for an empty path")
    func requestPort() throws {
        let url = try #require(URL(string: "http://example.com:8080"))
        let text = String(decoding: HTTPRequest.get(url, headers: []), as: UTF8.self)
        #expect(text.hasPrefix("GET / HTTP/1.1\r\nHost: example.com:8080\r\n"))
    }

    @Test("drops header values that would inject new lines")
    func requestInjection() throws {
        let url = try #require(URL(string: "https://example.com/"))
        let text = String(decoding: HTTPRequest.get(url, headers: [("X-Test", "a\r\nEvil: 1")]), as: UTF8.self)
        #expect(!text.contains("Evil"))
    }

    @Test("renders a POST request with its body and length")
    func post() throws {
        let url = try #require(URL(string: "https://www.youtube.com/youtubei/v1/player?prettyPrint=false"))
        let body = Data(#"{"videoId":"abc"}"#.utf8)
        let text = String(decoding: HTTPRequest.post(url, headers: [("Content-Type", "application/json")], body: body), as: UTF8.self)
        #expect(text.hasPrefix("POST /youtubei/v1/player?prettyPrint=false HTTP/1.1\r\nHost: www.youtube.com\r\n"))
        #expect(text.contains("Content-Type: application/json\r\nContent-Length: 17\r\n"))
        #expect(text.hasSuffix("Connection: close\r\n\r\n{\"videoId\":\"abc\"}"))
    }

    @Test("a response read only up to a limit gives the body that arrived")
    func truncatedOnPurpose() throws {
        let plain = try HTTPResponse.parse(raw("HTTP/1.1 200 OK\r\nContent-Length: 10\r\n\r\nabc"), truncated: true)
        #expect(String(decoding: plain.body, as: UTF8.self) == "abc")
        let chunked = try HTTPResponse.parse(raw("HTTP/1.1 200 OK\r\nTransfer-Encoding: chunked\r\n\r\n4\r\nWiki\r\nFF\r\nped"),
                                             truncated: true)
        #expect(String(decoding: chunked.body, as: UTF8.self) == "Wikiped")
        let cutInSize = try HTTPResponse.parse(raw("HTTP/1.1 200 OK\r\nTransfer-Encoding: chunked\r\n\r\n4\r\nWiki\r\nF"),
                                               truncated: true)
        #expect(String(decoding: cutInSize.body, as: UTF8.self) == "Wiki")
    }

    @Test("parses status, headers and a Content-Length body")
    func contentLength() throws {
        let response = try HTTPResponse.parse(raw("HTTP/1.1 200 OK\r\nContent-Type: text/plain\r\nContent-Length: 5\r\n\r\nhelloEXTRA"))
        #expect(response.status == 200)
        #expect(response.header("content-type") == "text/plain")
        #expect(String(decoding: response.body, as: UTF8.self) == "hello")
    }

    @Test("a SHOUTcast server's ICY status line, read up to the end of its headers")
    func icy() throws {
        let response = try HTTPResponse.parse(raw("ICY 200 OK\r\nicy-name: Radyo\r\n\r\n\u{1}\u{2}"), truncated: true)
        #expect(response.status == 200)
        #expect(response.header("icy-name") == "Radyo")
        #expect(throws: HTTPResponseError.malformed) { try HTTPResponse.parse(raw("SPAM 200 OK\r\n\r\n")) }
    }

    @Test("reads the body until the connection closed when no length is given")
    func untilClose() throws {
        let response = try HTTPResponse.parse(raw("HTTP/1.0 404 Not Found\r\n\r\nnope"))
        #expect(response.status == 404)
        #expect(String(decoding: response.body, as: UTF8.self) == "nope")
    }

    @Test("decodes a chunked body with extensions and trailers")
    func chunked() throws {
        let response = try HTTPResponse.parse(raw(
            "HTTP/1.1 200 OK\r\nTransfer-Encoding: chunked\r\n\r\n4;ext=1\r\nWiki\r\n6\r\npedia \r\nE\r\nin \r\n\r\nchunks.\r\n0\r\nExpires: never\r\n\r\n"))
        #expect(String(decoding: response.body, as: UTF8.self) == "Wikipedia in \r\n\r\nchunks.")
    }

    @Test("rejects a chunk longer than the data that arrived")
    func truncatedChunk() {
        #expect(throws: HTTPResponseError.malformed) {
            try HTTPResponse.parse(Data("HTTP/1.1 200 OK\r\nTransfer-Encoding: chunked\r\n\r\nFF\r\nshort".utf8))
        }
    }

    @Test("rejects chunk sizes that would overflow", arguments: ["7FFFFFFFFFFFFFFF", "FFFFFFFFFFFFFFFFFF", "-5"])
    func hugeChunk(size: String) {
        #expect(throws: HTTPResponseError.malformed) {
            try HTTPResponse.parse(Data("HTTP/1.1 200 OK\r\nTransfer-Encoding: chunked\r\n\r\n\(size)\r\nabc\r\n0\r\n\r\n".utf8))
        }
    }

    @Test("rejects a body shorter than its Content-Length")
    func shortBody() {
        #expect(throws: HTTPResponseError.malformed) {
            try HTTPResponse.parse(Data("HTTP/1.1 200 OK\r\nContent-Length: 10\r\n\r\nabc".utf8))
        }
    }

    @Test("knows when a response is complete before the connection closes")
    func completeness() {
        #expect(HTTPResponse.isComplete(raw("HTTP/1.1 200 OK\r\nContent-Length: 3\r\n\r\nabc")))
        #expect(!HTTPResponse.isComplete(raw("HTTP/1.1 200 OK\r\nContent-Length: 5\r\n\r\nabc")))
        #expect(HTTPResponse.isComplete(raw("HTTP/1.1 200 OK\r\nTransfer-Encoding: chunked\r\n\r\n3\r\nabc\r\n0\r\n\r\n")))
        #expect(!HTTPResponse.isComplete(raw("HTTP/1.1 200 OK\r\nTransfer-Encoding: chunked\r\n\r\n3\r\nabc\r\n")))
        #expect(!HTTPResponse.isComplete(raw("HTTP/1.1 200 OK\r\n\r\nuntil close")))
        #expect(!HTTPResponse.isComplete(raw("HTTP/1.1 200 OK\r\nContent-")))
    }

    @Test("rejects compressed bodies it cannot decode")
    func compressed() {
        #expect(throws: HTTPResponseError.unsupportedEncoding) {
            try HTTPResponse.parse(Data("HTTP/1.1 200 OK\r\nContent-Encoding: br\r\n\r\nxx".utf8))
        }
    }

    @Test("rejects responses without a valid status line", arguments: ["", "garbage\r\n\r\n", "HTTP/1.1 abc OK\r\n\r\n"])
    func malformed(text: String) {
        #expect(throws: HTTPResponseError.malformed) { try HTTPResponse.parse(Data(text.utf8)) }
    }

    @Test("finds the redirect target relative to the request")
    func redirect() throws {
        let response = try HTTPResponse.parse(raw("HTTP/1.1 302 Found\r\nLocation: /next?a=1\r\nContent-Length: 0\r\n\r\n"))
        let base = try #require(URL(string: "https://example.com/start"))
        #expect(response.redirectTarget(from: base)?.absoluteString == "https://example.com/next?a=1")
        #expect(try HTTPResponse.parse(raw("HTTP/1.1 200 OK\r\nLocation: /x\r\n\r\n")).redirectTarget(from: base) == nil)
    }
}
