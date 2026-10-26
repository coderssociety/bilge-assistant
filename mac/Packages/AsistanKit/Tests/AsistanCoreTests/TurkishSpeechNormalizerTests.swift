import Testing
@testable import AsistanCore

@Suite("TurkishNumberWords")
struct TurkishNumberWordsTests {
    @Test("cardinal numbers", arguments: [
        (0, "sıfır"), (7, "yedi"), (10, "on"), (15, "on beş"), (100, "yüz"), (101, "yüz bir"),
        (1000, "bin"), (1001, "bin bir"), (2026, "iki bin yirmi altı"), (17_350, "on yedi bin üç yüz elli"),
        (1_000_000, "bir milyon"), (2_500_000_000, "iki milyar beş yüz milyon"), (-4, "eksi dört"),
    ])
    func cardinals(value: Int, expected: String) {
        #expect(TurkishNumberWords.cardinal(value) == expected)
    }
}

@Suite("TurkishSpeechNormalizer")
struct TurkishSpeechNormalizerTests {
    @Test("verbalizes text for speech", arguments: [
        ("Saat 14:30", "Saat on dört otuz"),
        ("Saat 09:05'te", "Saat dokuz sıfır beşte"),
        ("Saat 14.30'da", "Saat on dört otuzda"),
        ("Pil %25 dolu", "Pil yüzde yirmi beş dolu"),
        ("Sıcaklık 3,5 °C", "Sıcaklık üç virgül beş derece"),
        ("Toplam 1.250 TL", "Toplam bin iki yüz elli lira"),
        ("Fiyatı 99₺", "Fiyatı doksan dokuz lira"),
        ("1 $ kaç lira", "bir dolar kaç lira"),
        ("Bilet 40€", "Bilet kırk avro"),
        ("3 toplantın var", "üç toplantın var"),
        ("13.10.2026 tarihinde", "on üç ekim iki bin yirmi altı tarihinde"),
    ])
    func normalizes(input: String, expected: String) {
        #expect(TurkishSpeechNormalizer.normalize(input) == expected)
    }

    @Test("strips markdown that would be read aloud")
    func stripsMarkdown() {
        #expect(TurkishSpeechNormalizer.normalize("**Önemli:** `ls` komutu") == "Önemli: ls komutu")
    }

    @Test("strips emphasis and emoji but keeps word-internal symbols", arguments: [
        ("En bilinen romanı *Kürk Mantolu Madonna*.", "En bilinen romanı Kürk Mantolu Madonna."),
        ("Ankara başkent oldu. 🇹🇷", "Ankara başkent oldu."),
        ("Mona Lisa'yı Leonardo da Vinci çizdi. 🎨😊", "Mona Lisa'yı Leonardo da Vinci çizdi."),
        ("Teşekkürler ❤️ görüşürüz 👨‍👩‍👧", "Teşekkürler görüşürüz"),
        ("dosya_adi.txt hazır", "dosya_adi.txt hazır"),
        ("7 * 24 eder", "yedi * yirmi dört eder"),
        ("3*(4+5) kaç", "üç*(dört+beş) kaç"),
        ("_önemli_ not", "önemli not"),
    ])
    func stripsEmphasisAndEmoji(input: String, expected: String) {
        #expect(TurkishSpeechNormalizer.normalize(input) == expected)
    }
}
