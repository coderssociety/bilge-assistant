import Testing
@testable import AsistanCore

@Suite("WakePhraseMatcher")
struct WakePhraseMatcherTests {
    let matcher = WakePhraseMatcher(phrase: "Asistan")

    @Test("matches the phrase at the start and returns the command after it", arguments: [
        ("Asistan, Safari'yi aç.", "Safari'yi aç."),
        ("hey asistan saat kaç", "saat kaç"),
        ("Asistanım müziği durdur", "müziği durdur"),
        ("asisstan sesi kıs", "sesi kıs"),
        ("A sistan, ekranı kilitle", "ekranı kilitle"),
        ("Şey, asistan, pil durumu nedir?", "pil durumu nedir?"),
    ])
    func matches(transcript: String, command: String) {
        #expect(matcher.match(transcript)?.command == command)
    }

    @Test("a bare wake phrase matches with an empty command")
    func bare() {
        let match = matcher.match("Asistan?")
        #expect(match != nil)
        #expect(match?.command == "")
    }

    @Test("does not trigger on unrelated speech", arguments: [
        "Bugün asistan olarak işe başladım",
        "İstanbul'a gidiyorum",
        "Asansör yine bozulmuş",
        "",
    ])
    func rejects(transcript: String) {
        #expect(matcher.match(transcript) == nil)
    }

    @Test("supports custom names and multi-word phrases")
    func customPhrase() {
        #expect(WakePhraseMatcher(phrase: "Defne").match("Hey Defne ışıkları kapat")?.command == "ışıkları kapat")
        #expect(WakePhraseMatcher(phrase: "Hey Defne").match("hey defne saat kaç")?.command == "saat kaç")
    }

    @Test("stricter sensitivity rejects near misses")
    func sensitivity() {
        let strict = WakePhraseMatcher(phrase: "Asistan", minimumSimilarity: 0.95)
        #expect(strict.match("asisstan sesi kıs") == nil)
        #expect(strict.match("asistan sesi kıs") != nil)
    }
}
