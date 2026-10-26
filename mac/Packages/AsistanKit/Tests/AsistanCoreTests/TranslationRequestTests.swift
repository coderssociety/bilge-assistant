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
        ("bunu Lehçeye çevir", "pl"),
        ("haberleri Lehçe oku", "pl"),
        ("Fransızca da söyle", "fr"),
        ("Türkçe yazılmış maili İngilizce oku", "en"),
        ("İngilizce yazar mısın", "en"),
    ])
    func target(command: String, code: String) {
        #expect(TranslationRequest.target(in: command)?.code == code)
    }

    @Test("requests that only mention a language have no target", arguments: [
        "Maillerimi oku", "İngilizce maili aç", "Türkçe haberler", "fincanı yıka", "I speak English",
        "Karadeniz lehçesini anlat", "Ege lehçesine çevir", "Almanca da biliyor musun", "İngilizce yazılmış maili oku",
        "İngilizce yazılan maili oku", "Almanca konuşan biri var mı", "Fransızca konuşulan ülkeleri say",
    ])
    func noTarget(command: String) {
        #expect(TranslationRequest.target(in: command) == nil)
    }

    @Test("a routine's command keeps the language it is to be read in")
    func routineCommand() throws {
        let routine = try #require(RoutineRequest.parse("her sabah 8'de haberleri İngilizce oku", language: .turkish))
        #expect(TranslationRequest.target(in: routine.command)?.code == "en")
    }
}
