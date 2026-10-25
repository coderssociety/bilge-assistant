import Foundation

public struct BrowserTab: Sendable, Equatable {
    /// The browser's bundle identifier.
    public let browser: String
    public let title: String
    public let url: URL?
    /// The tab shown in its window.
    public let isActive: Bool

    public init(browser: String, title: String, url: URL?, isActive: Bool) {
        self.browser = browser
        self.title = title
        self.url = url
        self.isActive = isActive
    }
}

/// Music playing in a browser, known from its tabs' addresses and titles (no page is scripted) and from which apps
/// are making sound.
public enum BrowserMedia {
    private static let field: Character = "\t"
    private static let youTubeHosts: Set<String> = ["youtube.com", "www.youtube.com", "m.youtube.com"]
    private static let youTubeVideoPaths = ["/shorts/", "/live/", "/embed/"]
    /// Safari's pages play through WebKit's shared processes, which carry WebKit's identifier rather than Safari's.
    private static let webKitProcesses: Set<String> = ["com.apple.webkit.gpu", "com.apple.webkit.webcontent"]
    private static let safari = "com.apple.Safari"
    /// Browsers and media apps, whose sound the play/pause key controls. A call or a game also makes sound, but the key
    /// would pass it by and resume a paused Spotify.
    private static let mediaProcesses = webKitProcesses.union([
        "com.apple.safari", "com.google.chrome", "com.microsoft.edgemac", "com.brave.browser", "company.thebrowser.browser",
        "org.mozilla.firefox", "com.operasoftware.opera", "com.vivaldi.vivaldi",
        "com.apple.podcasts", "com.apple.tv", "com.apple.quicktimeplayerx", "org.videolan.vlc", "com.colliderli.iina",
        "com.deezer.deezer-desktop", "com.tidal.desktop", "com.amazon.music", "au.com.shiftyjelly.pocketcasts",
    ])

    /// The service whose player the address is: a YouTube video, or a YouTube Music, Deezer, Apple Music or Spotify page
    /// (their players keep playing while their other pages are browsed).
    public static func service(at url: URL) -> MusicService? {
        guard let host = url.host()?.lowercased(), url.scheme?.lowercased() == "https" || url.scheme?.lowercased() == "http"
        else { return nil }
        let path = url.path()
        if host == "music.youtube.com" { return .youTubeMusic }
        if youTubeHosts.contains(host), path == "/watch" || youTubeVideoPaths.contains(where: path.hasPrefix) { return .youTube }
        if host == "youtu.be" { return .youTube }
        if host == "deezer.com" || host.hasSuffix(".deezer.com") { return .deezer }
        if host == "music.apple.com" { return .appleMusic }
        if host == "open.spotify.com" { return .spotify }
        return nil
    }

    /// The tabs as the tab script prints them, a line each: "true", the address and the title, split by tabs.
    public static func tabs(fromScript output: String, browser: String) -> [BrowserTab] {
        output.split(separator: "\n").compactMap { line in
            let parts = line.split(separator: field, maxSplits: 2, omittingEmptySubsequences: false).map(String.init)
            guard parts.count == 3 else { return nil }
            return BrowserTab(browser: browser, title: parts[2], url: URL(string: parts[1]), isActive: parts[0] == "true")
        }
    }

    /// The music tab most likely to be playing: in a browser that is making sound first, then a tab in front.
    public static func mediaTab(in tabs: [BrowserTab], sounding: Set<String>) -> (tab: BrowserTab, service: MusicService)? {
        let media = tabs.compactMap { tab in tab.url.flatMap(service(at:)).map { (tab: tab, service: $0) } }
        let ranked = media.enumerated().sorted { lhs, rhs in
            let left = (sounding.contains(lhs.element.tab.browser), lhs.element.tab.isActive)
            let right = (sounding.contains(rhs.element.tab.browser), rhs.element.tab.isActive)
            if left != right { return left.0 != right.0 ? left.0 : left.1 }
            return lhs.offset < rhs.offset
        }
        return ranked.first?.element
    }

    /// Which of the running `apps` are making sound, given the bundle identifiers of the audio processes that are
    /// playing. A browser plays through a helper ("com.google.Chrome.helper"), Safari through WebKit's processes.
    public static func sounding(_ apps: [String], processes: [String]) -> Set<String> {
        let playing = processes.map { $0.lowercased() }
        return Set(apps.filter { app in
            let id = app.lowercased()
            if playing.contains(where: { $0 == id || $0.hasPrefix(id + ".") }) { return true }
            return app == safari && playing.contains(where: webKitProcesses.contains)
        })
    }

    /// Whether a browser or a media app other than Music and Spotify is making sound. A wrong yes would let a pause press
    /// the play/pause key and start whatever is paused, so only known media processes count.
    public static func othersSounding(_ processes: [String]) -> Bool {
        processes.map { $0.lowercased() }.contains { id in
            mediaProcesses.contains { id == $0 || id.hasPrefix($0 + ".") }
        }
    }
}
