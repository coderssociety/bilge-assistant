import Testing
@testable import AsistanCore

@Suite("RouteGuard")
struct RouteGuardTests {
    @Test("web search needs an explicit search request", arguments: [
        ("Türkiye'nin başkenti neresi", "searchWeb", "conversation"),
        ("En uzun nehir hangisi", "searchWeb", "conversation"),
        ("YouTube'da kedi videoları ara", "searchWeb", "searchWeb"),
        ("Google'da en yakın eczane", "searchWeb", "searchWeb"),
        ("Haritalarda Kadıköy'ü göster", "searchWeb", "searchWeb"),
        ("Atatürk'ü internette arar mısın", "searchWeb", "searchWeb"),
    ])
    func webSearch(command: String, routed: String, expected: String) {
        #expect(RouteGuard.review(action: routed, command: command) == expected)
    }

    @Test("closing a window is not quitting the app", arguments: [
        ("Safari penceresini kapat", "quitApp", "windowControl"),
        ("Safari'yi kapat", "quitApp", "quitApp"),
    ])
    func closeWindow(command: String, routed: String, expected: String) {
        #expect(RouteGuard.review(action: routed, command: command) == expected)
    }

    @Test("system actions cover lock, sleep, appearance, Focus and power", arguments: [
        ("Odak modunu aç", "systemAction", "systemAction"),
        ("Rahatsız etme modunu aç", "systemAction", "systemAction"),
        ("Uyku odağını aç", "systemAction", "systemAction"),
        ("Rahatsız etme modunu aç", "runShortcut", "systemAction"),
        ("Bilgisayarı yeniden başlat", "systemAction", "systemAction"),
        ("Mac'i kapat", "quitApp", "systemAction"),
        ("Safari'yi kapat", "quitApp", "quitApp"),
        ("Sabah rutini kestirmesini çalıştır", "runShortcut", "runShortcut"),
        ("Odak kestirmesini çalıştır", "runShortcut", "runShortcut"),
        ("Bluetooth'u kapat", "setWiFi", "setBluetooth"),
        ("Bluetooth ayarlarını aç", "openSettings", "openSettings"),
        ("Parlaklığı yüzde 50 yap", "runShortcut", "setBrightness"),
        ("Ekranı kilitle", "systemAction", "systemAction"),
        ("Bilgisayarı uyut", "systemAction", "systemAction"),
        ("Karanlık moda geç", "systemAction", "systemAction"),
        ("Aydınlık moda geç", "systemAction", "systemAction"),
        ("Parlaklığı artır", "systemAction", "setBrightness"),
        ("Ekranı karart", "systemAction", "systemAction"),
        ("ekranı kapat", "systemAction", "systemAction"),
        ("Ekran parlaklığını kapat", "systemAction", "setBrightness"),
        ("Işıkları aç", "systemAction", "runShortcut"),
    ])
    func systemActions(command: String, routed: String, expected: String) {
        #expect(RouteGuard.review(action: routed, command: command) == expected)
    }

    @Test("'… aç' is opening an app, not reading the calendar", arguments: [
        ("Takvimi aç", "readCalendar", "openApp"),
        ("Takvim uygulamasını açar mısın", "readCalendar", "openApp"),
        ("Bugün takvimde ne var", "readCalendar", "readCalendar"),
        ("Yarın takvimimde ne var", "readCalendar", "readCalendar"),
    ])
    func calendarOpen(command: String, routed: String, expected: String) {
        #expect(RouteGuard.review(action: routed, command: command) == expected)
    }

    @Test("other actions pass through unchanged")
    func passthrough() {
        #expect(RouteGuard.review(action: "openApp", command: "Safari'yi aç") == "openApp")
        #expect(RouteGuard.review(action: "conversation", command: "nasılsın") == "conversation")
    }

    @Test("bare acknowledgements and greetings never trigger an action", arguments: [
        "Evet", "Evet.", "Hayır", "tamam", "Teşekkürler", "teşekkür ederim", "sağ ol", "çok sağ ol", "eyvallah",
        "Günaydın", "Merhaba", "iyi akşamlar", "nasılsın",
    ])
    func acknowledgements(command: String) {
        #expect(RouteGuard.preRoute(command) == "conversation")
    }

    @Test("real commands are left to the model", arguments: [
        "Safari'yi aç", "evet Safari'yi aç lütfen", "saat kaç", "dosyayı sil",
    ])
    func commandsGoToModel(command: String) {
        #expect(RouteGuard.preRoute(command) == nil)
    }

    @Test("dictation wins over time words", arguments: [
        ("şunu yaz yarın sabah görüşelim", "setTimer"), ("buraya merhaba nasılsın yaz", "conversation"),
        ("Ahmet'e 10 dakika sonra geliyorum yaz", "setTimer"),
    ])
    func dictation(command: String, modelAction: String) {
        #expect(RouteGuard.review(action: modelAction, command: command) == "typeText")
    }

    @Test("summer is not dictation", arguments: ["yaz şarkıları listemi çal", "yaz tatili ne zaman"])
    func summer(command: String) {
        #expect(RouteGuard.review(action: "playMusic", command: command) == "playMusic")
    }

    @Test("weather needs a weather word", arguments: [
        ("Bana bir tavsiye ver", "conversation"), ("yarın yağmur yağacak mı", "weather"), ("dışarısı kaç derece", "weather"),
        ("şemsiye alayım mı", "weather"),
    ])
    func weather(command: String, expected: String) {
        #expect(RouteGuard.review(action: "weather", command: command) == expected)
    }

    @Test("a weather follow-up without weather words stays with the weather")
    func weatherFollowUp() {
        #expect(RouteGuard.review(action: "weather", command: "peki yarın?", previousAction: "weather") == "weather")
        #expect(RouteGuard.review(action: "weather", command: "peki yarın?", previousAction: "news") == "conversation")
        #expect(EnglishRouteGuard.review(action: "weather", command: "what about tomorrow", previousAction: "weather") == "weather")
    }

    @Test("a place to show on a map is a search, not just opening the app")
    func mapSearch() {
        #expect(RouteGuard.review(action: "openApp", command: "Haritalarda Kadıköy'ü göster") == "searchWeb")
        #expect(RouteGuard.review(action: "openApp", command: "Haritaları aç") == "openApp")
    }

    // Commands reach the guard number- and time-resolved: "yirmi dakika" is "20 dakika", "akşam sekizde" is "20:00".
    @Test("a reminder for another day, or with no time, is a to-do, not an in-app timer", arguments: [
        ("Yarın sabah süt almayı hatırlat", "setTimer", "addReminder"),
        ("Süt almayı unutma diye hatırlat", "setTimer", "addReminder"),
        ("Pazartesi faturayı ödememi hatırlat", "setTimer", "addReminder"),
        ("yarın toplantıyı unutma", "setTimer", "addReminder"),
        ("20 dakika sonra çayı hatırlat", "setTimer", "setTimer"),
        ("20:00 ilacımı hatırlat", "setTimer", "setTimer"),
        ("10 dakikalık zamanlayıcı kur", "setTimer", "setTimer"),
    ])
    func reminderDay(command: String, action: String, expected: String) {
        #expect(RouteGuard.review(action: action, command: command) == expected)
    }

    @Test("reading a file is readDocument, opening it stays files", arguments: [
        ("son indirdiğim PDF'i özetle", "readDocument"), ("indirdiğim belgede ne yazıyor", "readDocument"),
        ("son indirilen dosyayı oku", "readDocument"), ("raporun içeriğini anlat", "readDocument"),
        ("son indirdiğim PDF'i aç", "files"), ("Belgeler klasörünü göster", "files"),
    ])
    func readsFile(command: String, expected: String) {
        #expect(RouteGuard.review(action: "files", command: command) == expected)
    }

    @Test("undo is never taken for quitting an app")
    func undoIsNotQuit() {
        #expect(RouteGuard.review(action: "quitApp", command: "geri al") == "conversation")
        #expect(RouteGuard.review(action: "quitApp", command: "son işlemi geri al") == "conversation")
        #expect(RouteGuard.review(action: "quitApp", command: "Safari'yi kapat") == "quitApp")
    }

    @Test("clear encyclopedic questions are looked up on Wikipedia", arguments: [
        ("Mustafa Kemal Atatürk kimdir", "conversation", "wikipedia"),
        ("fotosentez nedir", "conversation", "wikipedia"),
        ("Everest hakkında bilgi ver", "conversation", "wikipedia"),
        ("nasılsın", "conversation", "conversation"),
        ("Everest'in yüksekliği ne kadar", "conversation", "conversation"),
        ("Osmanlı Devleti'nin kurucusu kimdir", "conversation", "conversation"),
        ("bu hata nedir", "readScreen", "readScreen"),
        ("pil durumu nedir", "batteryStatus", "batteryStatus"),
        ("saat kaç", "currentDateTime", "currentDateTime"),
    ])
    func wikipedia(command: String, routed: String, expected: String) {
        #expect(RouteGuard.review(action: routed, command: command) == expected)
    }

    @Test("gold goes to its own prices, currencies stay with the rates", arguments: [
        ("100 gram altın kaç lira", "exchangeRate", "goldPrice"),
        ("ons kaç dolar", "exchangeRate", "goldPrice"),
        ("dolar kaç lira", "exchangeRate", "exchangeRate"),
    ])
    func gold(command: String, routed: String, expected: String) {
        #expect(RouteGuard.review(action: routed, command: command) == expected)
    }
}
