import Testing
@testable import AsistanCore

@Suite("VolumeChange")
struct VolumeChangeTests {
    @Test("reads a signed amount from a volume change request", arguments: [
        ("sesi yüzde yirmi artır", 20),
        ("sesi yüzde yirmi kadar artırır mısın lütfen", 20),
        ("sesi on puan kıs", -10),
        ("sesi yüzde otuz azalt acaba", -30),
        ("sesi beş aç", 5),
    ])
    func amount(text: String, expected: Int) {
        #expect(VolumeChange.parse(TurkishNumberParser.digitize(text)) == expected)
    }

    @Test("is nil for target levels and requests without an amount", arguments: [
        "sesi yüzde yirmiye düşür", "sesi biraz artır", "sesi yüzde elli yap", "yüzde yirmi indirim var mı",
    ])
    func none(text: String) {
        #expect(VolumeChange.parse(TurkishNumberParser.digitize(text)) == nil)
    }
}
