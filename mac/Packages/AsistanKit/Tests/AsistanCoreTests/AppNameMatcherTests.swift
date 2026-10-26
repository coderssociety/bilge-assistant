import Testing
@testable import AsistanCore

@Suite("AppNameMatcher")
struct AppNameMatcherTests {
    let matcher = AppNameMatcher(apps: [
        .init(id: "safari", names: ["Safari"]),
        .init(id: "calendar", names: ["Takvim", "Calendar"]),
        .init(id: "calculator", names: ["Hesap Makinesi", "Calculator"]),
        .init(id: "word", names: ["Microsoft Word"]),
        .init(id: "vscode", names: ["Visual Studio Code"]),
        .init(id: "xcode", names: ["Xcode"]),
        .init(id: "spotify", names: ["Spotify"]),
        .init(id: "music", names: ["Müzik", "Music"]),
        .init(id: "mail", names: ["Mail"]),
    ])

    @Test("finds apps by localized name, English name, suffixes and near misses", arguments: [
        ("safari", "safari"), ("Safari'yi", "safari"), ("takvim", "calendar"), ("Calendar", "calendar"),
        ("hesap makinesi", "calculator"), ("hesap makinesini", "calculator"), ("word", "word"),
        ("spotifay", "spotify"), ("Xcode", "xcode"), ("müziği", "music"), ("mail uygulaması", "mail"),
        ("visual studio code", "vscode"),
    ])
    func finds(query: String, expected: String) {
        #expect(matcher.bestMatch(for: query)?.id == expected)
    }

    @Test("returns nil when nothing is close", arguments: ["photoshop", "", "uygulama"])
    func noMatch(query: String) {
        #expect(matcher.bestMatch(for: query) == nil)
    }
}
