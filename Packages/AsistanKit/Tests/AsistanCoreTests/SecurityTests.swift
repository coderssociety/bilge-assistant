import Foundation
import Testing
@testable import AsistanCore

@Suite("Security helpers")
struct SecurityTests {
    @Test("only public addresses are fetchable", arguments: [
        ("8.8.8.8", true), ("151.101.1.69", true), ("2606:4700::6810:84e5", true),
        ("127.0.0.1", false), ("10.1.2.3", false), ("192.168.1.30", false), ("172.20.0.5", false), ("169.254.169.254", false),
        ("100.64.0.1", false), ("0.0.0.0", false), ("::1", false), ("::", false), ("fe80::1", false), ("fd12:3456::1", false),
        ("::ffff:192.168.1.1", false), ("::ffff:8.8.8.8", true), ("999.1.1.1", false), ("abc", false),
        ("64:ff9b::192.168.1.1", false), ("64:ff9b::8.8.8.8", true), ("fec0::1", false),
    ])
    func addresses(address: String, isPublic: Bool) {
        #expect(NetworkAddress.isPublic(address) == isPublic)
    }

    @Test("local host names", arguments: [("localhost", true), ("router.local", true), ("nas", true), ("printer.lan", true),
                                          ("ntv.com.tr", false), ("api.open-meteo.com", false)])
    func names(host: String, isLocal: Bool) {
        #expect(NetworkAddress.isLocalName(host) == isLocal)
    }

    @Test("typed text cannot press Return, Tab or Escape")
    func typed() {
        #expect(TypedText.sanitized("merhaba\rdünya\tnasılsın\u{1B}\u{2028}son\u{85}x\n") == "merhaba dünya nasılsın son x")
        #expect(TypedText.sanitized("👩‍💻 kod") == "👩‍💻 kod")
    }

    @Test("sending needs a clear yes", arguments: [
        ("evet", ConfirmationParser.Answer.confirmed), ("gönder", .confirmed), ("evet gönder", .confirmed),
        ("tamam", .unclear), ("peki", .unclear), ("yap", .unclear), ("hayır", .rejected),
    ])
    func strict(answer: String, expected: ConfirmationParser.Answer) {
        #expect(ConfirmationParser.parse(answer, strict: true) == expected)
    }

    @Test("unclosed tags do not make extraction slow")
    func pathologicalHTML() {
        let page = String(repeating: "<form a>x ", count: 60_000) + "<p>son</p>"
        let started = Date()
        _ = HTMLText.extract(page)
        #expect(Date().timeIntervalSince(started) < 2)
    }
}
