import Testing
@testable import AsistanCore

@Suite("TurkishNumberParser")
struct TurkishNumberParserTests {
    @Test("converts spelled-out numbers to digits, keeping case suffixes", arguments: [
        ("üç yüz yirminin yarısı kaç", "320'nin yarısı kaç"),
        ("on iki çarpı on beş", "12 çarpı 15"),
        ("kırk beş dakikalık zamanlayıcı", "45 dakikalık zamanlayıcı"),
        ("sesi elliye getir", "sesi 50'ye getir"),
        ("iki bin yirmi altı yılı", "2026 yılı"),
        ("bin beş yüz lira", "1500 lira"),
        ("yüz yirmi beşin yüzde on sekizi", "125'in yüzde 18'i"),
        ("on dakika sonra", "10 dakika sonra"),
        ("üç milyon iki yüz bin", "3200000"),
        ("sesi yüzde otuz yap", "sesi yüzde 30 yap"),
        ("bin iki yüzün yüzde yirmisi ne kadar", "1200'ün yüzde 20'si ne kadar"),
    ])
    func digitizes(input: String, expected: String) {
        #expect(TurkishNumberParser.digitize(input) == expected)
    }

    @Test("leaves non-numeric uses alone", arguments: [
        "bir not oluştur",
        "onu kapat",
        "ondan sonra müziği aç",
        "ona bir mesaj yaz",
        "masanın altında",
        "Safari'yi aç",
    ])
    func keepsWords(input: String) {
        #expect(TurkishNumberParser.digitize(input) == input)
    }

    @Test("bir counts when it is part of a larger number or before a unit")
    func birInContext() {
        #expect(TurkishNumberParser.digitize("bir milyon") == "1000000")
        #expect(TurkishNumberParser.digitize("bir dakika bekle") == "1 dakika bekle")
    }
}

@Suite("TurkishTimeOfDay")
struct TurkishTimeOfDayTests {
    @Test("resolves part-of-day expressions to 24-hour clock times", arguments: [
        ("akşam sekizde ilacımı hatırlat", "20:00'de ilacımı hatırlat"),
        ("Akşam sekizde ilacımı hatırlat", "20:00'de ilacımı hatırlat"),
        ("sabah yedide beni uyandır", "07:00'de beni uyandır"),
        ("öğleden sonra üç buçukta toplantı", "15:30'da toplantı"),
        ("gece on birde", "23:00'de"),
        ("gece ikide", "02:00'de"),
        ("öğlen on ikide", "12:00'de"),
        ("yarın sabah dokuz buçukta", "yarın 09:30'da"),
    ])
    func resolves(input: String, expected: String) {
        #expect(TurkishTimeOfDay.resolve(TurkishNumberParser.digitize(input)) == expected)
    }

    @Test("resolves quarter past and to, with or without a part of day", arguments: [
        ("sekize çeyrek kala uyandır", "7:45 uyandır"),
        ("dokuzu çeyrek geçe", "9:15"),
        ("akşam dokuzu on geçe", "21:10"),
        ("altıya beş kala", "5:55"),
        ("on ikiye yirmi kala", "11:40"),
        ("onu beş geçe", "10:05"),
        ("bire beş kala", "12:55"),
        ("biri çeyrek geçe", "1:15"),
        ("akşam sekize çeyrek kala", "19:45"),
        ("gece on ikiyi on geçe", "00:10"),
    ])
    func resolvesPastAndTo(input: String, expected: String) {
        #expect(TurkishTimeOfDay.resolve(TurkishNumberParser.digitize(input)) == expected)
    }

    @Test("leaves text without a part of day unchanged")
    func untouched() {
        #expect(TurkishTimeOfDay.resolve("10 dakika sonra") == "10 dakika sonra")
        #expect(TurkishTimeOfDay.resolve("onu 5 dakika sonra ara") == "onu 5 dakika sonra ara")
    }
}
