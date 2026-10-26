import Testing
@testable import AsistanCore

@Suite("English browser commands")
struct EnglishBrowserCommandTests {
    @Test("recognized", arguments: [
        ("Next tab", BrowserCommand?.some(.nextTab)), ("Go to the previous tab", .previousTab),
        ("Open a new tab", .newTab), ("Close this tab", .closeTab), ("Reopen the closed tab", .reopenTab),
        ("Bring back the tab I closed", .reopenTab), ("Switch to the third tab", .tab(3)), ("Go to tab 2", .tab(2)),
        ("Go to the last tab", .lastTab), ("Switch to the YouTube tab", .tabNamed("YouTube")),
        ("Go back", .back), ("Back", .back), ("Go forward", .forward), ("Refresh the page", .reload),
        ("Scroll down", .scrollDown), ("Page up", .scrollUp), ("Go to the top", .top), ("Scroll to the bottom", .bottom),
        ("Find price on this page", .find("price")), ("Search for return policy on the page", .find("return policy")),
    ])
    func parse(text: String, expected: BrowserCommand?) {
        #expect(BrowserCommand.parse(text, language: .english) == expected)
    }

    @Test("ordinary sentences are left to the router", arguments: [
        "I'll be back later today", "Turn the volume up", "Open Safari", "What's on the news", "Look up flights to Rome",
        "Search YouTube for cat videos",
    ])
    func ignored(text: String) {
        #expect(BrowserCommand.parse(text, language: .english) == nil)
    }
}
