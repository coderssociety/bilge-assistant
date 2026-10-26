import Foundation
import Testing
@testable import AsistanCore

@Suite("Browser media")
struct BrowserMediaTests {
    private let chrome = "com.google.Chrome"
    private let safari = "com.apple.Safari"

    @Test("music players' addresses name their service", arguments: [
        ("https://www.youtube.com/watch?v=NAHRpEqgcL4", MusicService.youTube),
        ("https://youtu.be/NAHRpEqgcL4", .youTube),
        ("https://m.youtube.com/shorts/aBcD_-12345", .youTube),
        ("https://music.youtube.com/library", .youTubeMusic),
        ("https://www.deezer.com/tr/track/16412320", .deezer),
        ("https://music.apple.com/tr/album/x/1?i=2", .appleMusic),
        ("https://open.spotify.com/", .spotify),
    ])
    func service(address: String, expected: MusicService) {
        #expect(BrowserMedia.service(at: URL(string: address)!) == expected)
    }

    @Test("other pages are not players", arguments: [
        "https://www.youtube.com/", "https://www.youtube.com/results?search_query=tarkan", "https://notdeezer.com/track/1",
        "https://example.com/watch?v=NAHRpEqgcL4", "file:///Users/x/music.mp3",
    ])
    func notPlayer(address: String) {
        #expect(BrowserMedia.service(at: URL(string: address)!) == nil)
    }

    @Test("the tab script's lines become tabs; a tab inside a title stays in it")
    func parse() {
        let output = "true\thttps://www.youtube.com/watch?v=NAHRpEqgcL4\tTARKAN - Kuzu Kuzu - YouTube\nfalse\thttps://example.com\tA\tB\nbroken line"
        let tabs = BrowserMedia.tabs(fromScript: output, browser: chrome)
        #expect(tabs.count == 2)
        #expect(tabs[0] == BrowserTab(browser: chrome, title: "TARKAN - Kuzu Kuzu - YouTube",
                                      url: URL(string: "https://www.youtube.com/watch?v=NAHRpEqgcL4"), isActive: true))
        #expect(tabs[1].title == "A\tB" && !tabs[1].isActive)
    }

    @Test("a music tab in a browser that is sounding wins, then one in front, then the first")
    func mediaTab() {
        let tabs = [
            BrowserTab(browser: safari, title: "Deezer", url: URL(string: "https://www.deezer.com/tr/"), isActive: false),
            BrowserTab(browser: chrome, title: "Haberler", url: URL(string: "https://example.com"), isActive: true),
            BrowserTab(browser: chrome, title: "Begonvil - YouTube Music", url: URL(string: "https://music.youtube.com/watch?v=tAT2nh_Smx0"), isActive: false),
            BrowserTab(browser: safari, title: "Kuzu Kuzu - YouTube", url: URL(string: "https://www.youtube.com/watch?v=NAHRpEqgcL4"), isActive: true),
        ]
        #expect(BrowserMedia.mediaTab(in: tabs, sounding: [chrome])?.service == .youTubeMusic)
        #expect(BrowserMedia.mediaTab(in: tabs, sounding: [])?.service == .youTube)
        #expect(BrowserMedia.mediaTab(in: Array(tabs.prefix(3)), sounding: [])?.service == .deezer)
        #expect(BrowserMedia.mediaTab(in: [tabs[1]], sounding: [chrome]) == nil)
    }

    @Test("browsers sound through their helpers, Safari through WebKit")
    func sounding() {
        let apps = [chrome, safari, "com.brave.Browser"]
        #expect(BrowserMedia.sounding(apps, processes: ["com.google.Chrome.helper"]) == [chrome])
        #expect(BrowserMedia.sounding(apps, processes: ["com.apple.WebKit.GPU"]) == [safari])
        #expect(BrowserMedia.sounding(apps, processes: ["com.google.chromecast"]).isEmpty)
    }

    @Test("only browsers and media apps outside Music and Spotify count as something else sounding")
    func othersSounding() {
        #expect(BrowserMedia.othersSounding(["com.google.Chrome.helper"]))
        #expect(BrowserMedia.othersSounding(["com.apple.WebKit.GPU"]))
        #expect(BrowserMedia.othersSounding(["com.apple.podcasts"]))
        #expect(BrowserMedia.othersSounding(["org.mozilla.firefox", "us.zoom.xos"]))
        #expect(!BrowserMedia.othersSounding(["com.spotify.client.helper", "com.apple.Music", "com.vrnsoft.Asistan"]))
        #expect(!BrowserMedia.othersSounding(["", "com.apple.speech.synthesisd", "com.apple.systemsoundserverd"]))
        #expect(!BrowserMedia.othersSounding([]))
    }

    @Test("calls and games do not count, so a pause does not press the key and resume Spotify")
    func callsAndGamesAreNotMedia() {
        #expect(!BrowserMedia.othersSounding(["us.zoom.xos", "com.microsoft.teams2", "com.hnc.Discord.helper", "com.valvesoftware.steam"]))
        #expect(!BrowserMedia.othersSounding(["com.google.chromecast"]))
    }
}
