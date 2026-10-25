import Testing
@testable import AsistanCore

@Suite("QuickIntentParser")
struct QuickIntentParserTests {
    func parse(_ text: String) -> QuickIntent? {
        QuickIntentParser.parse(TurkishTimeOfDay.resolve(TurkishNumberParser.digitize(text)))
    }

    @Test("recognizes everyday commands without the model", arguments: [
        ("Saat kaç", QuickIntent.dateTime),
        ("saat kaç oldu acaba", .dateTime),
        ("Bugün günlerden ne", .dateTime),
        ("ayın kaçı", .dateTime),
        ("Pil durumu nedir", .battery),
        ("şarjım ne kadar", .battery),
        ("Sesi yüzde otuz yap", .volume(.set(30))),
        ("sesi elliye getir", .volume(.set(50))),
        ("Sesi biraz kıs", .volume(.down)),
        ("sesi yükselt", .volume(.up)),
        ("Sesi kapat", .volume(.mute)),
        ("Müziği durdur", .media(.pause)),
        ("müziği başlat", .media(.play)),
        ("Sonraki şarkıya geç", .media(.next)),
        ("şarkıyı geç", .media(.next)),
        ("Bir önceki şarkıyı çal", .media(.previous)),
        ("Bu şarkının adı ne", .media(.nowPlaying)),
        ("Ekranı kilitle", .system(.lockScreen)),
        ("Mac'i kilitle", .system(.lockScreen)),
        ("Bilgisayarı uyut", .system(.sleep)),
        ("Karanlık modu aç", .system(.darkModeOn)),
        ("aydınlık moda geç", .system(.darkModeOff)),
        ("Bugün takvimde ne var", .calendar(.today)),
        ("Yarın takvimimde ne var", .calendar(.tomorrow)),
        ("Bu hafta neler var", .calendar(.thisWeek)),
        ("Anımsatıcılarımı oku", .reminders),
        ("Yüz yirminin yarısı kaç", .calculate("120 / 2")),
        ("on iki çarpı on beş", .calculate("12 * 15")),
        ("On dakikalık zamanlayıcı kur", .timer(seconds: 600)),
        ("beş dakika sonra beni uyar", .timer(seconds: 300)),
        ("Safari'yi aç", .openApp("Safari'yi")),
        ("hesap makinesini açar mısın", .openApp("hesap makinesini")),
        ("Spotify uygulamasını kapat", .quitApp("Spotify")),
        ("Terminali kapat", .quitApp("Terminali")),
        ("Ekranı kilitler misin", .system(.lockScreen)),
        ("Karanlık moda geçer misin", .system(.darkModeOn)),
        ("Şu an saat kaç acaba", .dateTime),
        ("Xcode'u açar mısın lütfen", .openApp("Xcode'u")),
        ("müziği durdurur musun", .media(.pause)),
        ("Yarım saat sonra beni uyar", .timer(seconds: 1800)),
        ("çeyrek saatlik zamanlayıcı kur", .timer(seconds: 900)),
        ("sekize çeyrek kala uyandır", .alarm(hour: 7, minute: 45)),
        ("beni dokuzu çeyrek geçe uyandır", .alarm(hour: 9, minute: 15)),
        ("bir buçuk saatlik zamanlayıcı kur", .timer(seconds: 5400)),
        ("üç çeyrek sonra uyar", .timer(seconds: 2700)),
        ("Belgeler klasörünü aç", .openFolder(.documents)),
        ("İndirilenleri aç", .openFolder(.downloads)),
        ("masaüstünü açar mısın", .openFolder(.desktop)),
        ("Bütün alarmları kapat", .timers(.cancelAll)),
        ("zamanlayıcıları iptal et", .timers(.cancelAll)),
        ("kurulu zamanlayıcılar neler", .timers(.list)),
        ("zamanlayıcıyı iptal et", .timers(.cancelOne)),
        ("Alarmı kapat", .timers(.cancelOne)),
        ("kaç dakika kaldı", .timers(.list)),
        ("zamanlayıcıda ne kadar kaldı", .timers(.list)),
        ("Kopyaladığım metni okur musun", .clipboard),
        ("panodaki yazıyı oku", .clipboard),
    ])
    func recognizes(command: String, expected: QuickIntent) {
        #expect(parse(command) == expected)
    }

    @Test("leaves anything unusual or richer to the model", arguments: [
        "Yirmi dakika sonra çayı hatırlat",          // has a label
        "Yarın saat onda diş hekimi randevusu ekle",  // writes to calendar
        "İndirilenler klasöründeki faturayı aç",       // a file, not the folder
        "Masaüstündeki deneme dosyasını aç",
        "alarmları kapat ve müziği aç",
        "çay zamanlayıcısını iptal et",              // names one timer
        "kopyaladığım metni Notlar'a yapıştır",
        "Rahatsız etme modunu aç",                    // Focus → Shortcuts
        "Sesi biraz aç ve müziği başlat",             // two actions
        "Türkiye'nin başkenti neresi",
        "Bluetooth'u kapat",
        "Bilgisayarı kapat",
        "ondan sonra müziği aç",
        "Saat kaçta toplantım var",
    ])
    func defers(command: String) {
        #expect(parse(command) == nil)
    }
}
