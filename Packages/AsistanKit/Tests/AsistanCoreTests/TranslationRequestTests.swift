import AsistanCore
import Testing

@Suite("TranslationRequest")
struct TranslationRequestTests {
    @Test("the language to read in, not the one the text is in", arguments: [
        ("İngilizce maili Türkçe oku", "tr"),
        ("Türkçe maili Fransızca olarak oku", "fr"),
        ("Bunu Almancaya çevir", "de"),
        ("haberleri İngilizce oku", "en"),
        ("mailin Türkçesini oku", "tr"),
        ("Fransızca de", "fr"),
        ("ispanyolca diline çevirerek anlat", "es"),
        ("Read my email in Turkish", "tr"),
        ("translate the news into German", "de"),
    ])
    func target(command: String, code: String) {
        #expect(TranslationRequest.target(in: command)?.code == code)
    }

    @Test("requests that only mention a language have no target", arguments: [
        "Maillerimi oku", "İngilizce maili aç", "Türkçe haberler", "fincanı yıka", "I speak English",
    ])
    func noTarget(command: String) {
        #expect(TranslationRequest.target(in: command) == nil)
    }
}
