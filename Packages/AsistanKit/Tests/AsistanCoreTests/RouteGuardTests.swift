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

    @Test("system actions are limited to lock, sleep and appearance", arguments: [
        ("Odak modunu aç", "systemAction", "runShortcut"),
        ("Rahatsız etme modunu aç", "systemAction", "runShortcut"),
        ("Uyku odağını aç", "systemAction", "runShortcut"),
        ("Ekranı kilitle", "systemAction", "systemAction"),
        ("Bilgisayarı uyut", "systemAction", "systemAction"),
        ("Karanlık moda geç", "systemAction", "systemAction"),
        ("Aydınlık moda geç", "systemAction", "systemAction"),
        ("Parlaklığı artır", "systemAction", "runShortcut"),
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
}
