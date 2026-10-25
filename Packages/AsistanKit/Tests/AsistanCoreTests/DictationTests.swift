import Testing
@testable import AsistanCore

@Suite("Dictation")
struct DictationTests {
    @Test("starting dictation", arguments: ["Dikte modunu başlat", "dikte başlat", "Dikteye başla", "Yazdırmaya başlayalım"])
    func start(text: String) {
        #expect(DictationCommand.isStart(text))
    }

    @Test("not a request to start dictation", arguments: ["Şunu yaz merhaba", "Dikte nedir", "yarın hava nasıl"])
    func notStart(text: String) {
        #expect(!DictationCommand.isStart(text))
    }

    @Test("commands inside dictation", arguments: [
        ("yeni satır", DictationCommand.newLine), ("Alt satıra geç", .newLine), ("yeni paragraf", .newParagraph),
        ("son cümleyi sil", .deleteLast), ("Sonuncuyu sil", .deleteLast), ("geri al", .deleteLast),
        ("dikteyi bitir", .finish), ("Dikte bitti", .finish), ("tamam bitti", .finish),
        ("Dikteyi durdur", .finish), ("yazmayı bırak", .finish), ("Dikteyi bitir lütfen.", .finish),
        ("dikteyi sonlandır", .finish), ("lütfen yeni satır", .newLine),
    ])
    func commands(text: String, expected: DictationCommand) {
        #expect(DictationCommand.parse(text) == expected)
    }

    @Test("ordinary speech is text, not a command", arguments: ["yeni bir satır alalım dedi", "sil baştan başladık", "lütfen", "artık bitti mi"])
    func text(text: String) {
        #expect(DictationCommand.parse(text) == nil)
    }

    @Test("spoken punctuation, spacing and capitals", arguments: [
        ("merhaba virgül nasılsın soru işareti", nil, "Merhaba, nasılsın?"),
        ("toplantı yarın nokta", "Merhaba.", " Toplantı yarın."),
        ("ve bütçe onaylandı", "Toplantı yarın", " ve bütçe onaylandı"),
        ("Fiyatlar şöyle iki nokta", nil, "Fiyatlar şöyle:"),
        ("tırnak aç selam tırnak kapat dedi", nil, "\"selam\" dedi"),
        ("yeni başlık", "Satır\n", "Yeni başlık"),
        ("Zaten noktalı.", "Önceki.", " Zaten noktalı."),
    ] as [(String, String?, String)])
    func formatting(spoken: String, previous: String?, expected: String) {
        #expect(DictationText.format(spoken, after: previous) == expected)
    }
}
