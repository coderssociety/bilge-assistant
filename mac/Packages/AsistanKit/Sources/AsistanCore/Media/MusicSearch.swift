import Foundation

public struct MusicTrack: Sendable, Equatable {
    public let title: String
    public let artist: String
    /// What plays it: a YouTube watch page, a Deezer or Apple Music track page.
    public let url: URL

    public init(title: String, artist: String, url: URL) {
        self.title = title
        self.artist = artist
        self.url = url
    }

    public var spoken: String { TrackName.spoken(title: title, artist: artist) }
}

/// The first matching tracks in the answers of the services' keyless searches (YouTube, YouTube Music, Deezer, iTunes),
/// and each service's search page for when nothing is found. The answers are someone else's data: anything missing or
/// odd is skipped, and only the services' own addresses come out.
public enum MusicSearch {
    public enum YouTubeClient: Sendable {
        case web, music

        var name: String { self == .web ? "WEB" : "WEB_REMIX" }
        var version: String { self == .web ? "2.20250101.00.00" : "1.20250101.01.00" }
        public var endpoint: URL {
            URL(string: self == .web ? "https://www.youtube.com/youtubei/v1/search?prettyPrint=false"
                : "https://music.youtube.com/youtubei/v1/search?prettyPrint=false")!
        }
    }

    /// Narrows a YouTube Music search to songs.
    private static let songsOnly = "EgWKAQIIAWoKEAkQBRAKEAMQBA=="
    private static let artistPage = "MUSIC_PAGE_TYPE_ARTIST"
    private static let appleHosts: Set<String> = ["music.apple.com", "itunes.apple.com"]
    private static let resultLimit = "10"
    private static let videoIDCharacters = CharacterSet(charactersIn: "ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789_-")
    private static let videoIDLength = 11
    private static let spotifySearchAllowed = CharacterSet(charactersIn: "abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789")
    private static let separatorBetweenArtistAndTitle = try! NSRegularExpression(pattern: #"\s[-–]\s"#)

    // MARK: - Requests

    /// The body of a youtubei search; `language` and `country` as "tr", "TR".
    public static func youTubeSearchBody(_ query: String, client: YouTubeClient, language: String, country: String) -> Data {
        var body: [String: Any] = [
            "context": ["client": ["clientName": client.name, "clientVersion": client.version, "hl": language,
                                   "gl": country.uppercased()]],
            "query": query,
        ]
        if client == .music { body["params"] = songsOnly }
        return (try? JSONSerialization.data(withJSONObject: body)) ?? Data()
    }

    public static func deezerSearchURL(_ query: String) -> URL? {
        url("https://api.deezer.com/search", [("q", query), ("limit", resultLimit)])
    }

    public static func iTunesSearchURL(_ query: String, country: String) -> URL? {
        url("https://itunes.apple.com/search", [("term", query), ("entity", "song"), ("country", country.lowercased()),
                                                ("limit", resultLimit)])
    }

    /// Where the user can pick from the results themselves.
    public static func searchPage(_ service: MusicService, query: String, country: String) -> URL? {
        let pathQuery = query.addingPercentEncoding(withAllowedCharacters: .urlPathAllowed.subtracting(["/", "?", "#"])) ?? ""
        return switch service {
        case .youTube: url("https://www.youtube.com/results", [("search_query", query)])
        case .youTubeMusic: url("https://music.youtube.com/search", [("q", query)])
        case .deezer: URL(string: "https://www.deezer.com/search/" + pathQuery)
        case .appleMusic: url("https://music.apple.com/\(country.lowercased())/search", [("term", query)])
        case .spotify: URL(string: "https://open.spotify.com/search/" + pathQuery)
        }
    }

    /// Spotify's own search, as its AppleScript cannot search or play a song by name.
    public static func spotifySearch(_ query: String) -> URL? {
        query.addingPercentEncoding(withAllowedCharacters: spotifySearchAllowed).flatMap { URL(string: "spotify:search:" + $0) }
    }

    /// Any YouTube video plays in YouTube Music too.
    public static func onYouTubeMusic(_ track: MusicTrack) -> MusicTrack {
        guard var components = URLComponents(url: track.url, resolvingAgainstBaseURL: false),
              components.host == "www.youtube.com" else { return track }
        components.host = "music.youtube.com"
        return MusicTrack(title: track.title, artist: track.artist, url: components.url ?? track.url)
    }

    /// The same page for an app that takes the web addresses under its own scheme: Deezer's `deezer://`, Music's `music://`.
    public static func appURL(_ url: URL, scheme: String) -> URL? {
        guard var components = URLComponents(url: url, resolvingAgainstBaseURL: false), components.scheme == "https" else {
            return nil
        }
        components.scheme = scheme
        return components.url
    }

    // MARK: - Answers

    /// Videos of a youtubei search on the WEB client; channels, playlists, shorts, ads, shelves and upcoming
    /// premieres are passed over.
    public static func youTubeVideos(_ data: Data) -> [MusicTrack] {
        let sections = list(path(json(data), "contents", "twoColumnSearchResultsRenderer", "primaryContents",
                                 "sectionListRenderer", "contents"))
        return sections.flatMap { list(path($0, "itemSectionRenderer", "contents")) }.compactMap { item in
            guard let video = path(item, "videoRenderer") as? [String: Any],
                  path(video, "navigationEndpoint", "reelWatchEndpoint") == nil, video["upcomingEventData"] == nil,
                  let id = videoID(video["videoId"]), let title = runs(video["title"]),
                  let url = URL(string: "https://www.youtube.com/watch?v=\(id)") else { return nil }
            let (name, owner) = TrackName.cleaned(title, artist: runs(video["ownerText"]) ?? "")
            // "Artist - Song" already; a channel's name in front of any other title says little.
            let saysArtist = separatorBetweenArtistAndTitle.firstMatch(in: name, range: NSRange(name.startIndex..., in: name)) != nil
            return MusicTrack(title: name, artist: saysArtist ? "" : owner, url: url)
        }
    }

    /// Songs of a youtubei search on YouTube Music's WEB_REMIX client.
    public static func youTubeMusicSongs(_ data: Data) -> [MusicTrack] {
        let tabs = list(path(json(data), "contents", "tabbedSearchResultsRenderer", "tabs"))
        let sections = tabs.flatMap { list(path($0, "tabRenderer", "content", "sectionListRenderer", "contents")) }
        return sections.flatMap { list(path($0, "musicShelfRenderer", "contents")) }.compactMap { item in
            let song = path(item, "musicResponsiveListItemRenderer")
            let columns = list(path(song, "flexColumns"))
            guard let id = videoID(path(song, "playlistItemData", "videoId")), let first = columns.first,
                  let title = runs(path(first, "musicResponsiveListItemFlexColumnRenderer", "text")),
                  let url = URL(string: "https://music.youtube.com/watch?v=\(id)") else { return nil }
            return MusicTrack(title: title, artist: artists(columns.dropFirst().first), url: url)
        }
    }

    /// Tracks of api.deezer.com/search that can be played.
    public static func deezerTracks(_ data: Data) -> [MusicTrack] {
        list(path(json(data), "data")).compactMap { item in
            guard let item = item as? [String: Any], (item["type"] as? String ?? "track") == "track",
                  item["readable"] as? Bool != false, let id = integer(item["id"]), id > 0,
                  let title = (item["title"] as? String)?.trimmingCharacters(in: .whitespaces), !title.isEmpty,
                  let url = URL(string: "https://www.deezer.com/track/\(id)") else { return nil }
            let artist = (path(item, "artist", "name") as? String)?.trimmingCharacters(in: .whitespaces) ?? ""
            return MusicTrack(title: title, artist: artist, url: url)
        }
    }

    /// Songs of the iTunes Search API, by their Apple Music page.
    public static func iTunesSongs(_ data: Data) -> [MusicTrack] {
        list(path(json(data), "results")).compactMap { item in
            guard let item = item as? [String: Any], item["kind"] as? String == "song",
                  let title = (item["trackName"] as? String)?.trimmingCharacters(in: .whitespaces), !title.isEmpty,
                  let address = item["trackViewUrl"] as? String, let url = URL(string: address), url.scheme == "https",
                  let host = url.host()?.lowercased(), appleHosts.contains(host) else { return nil }
            let artist = (item["artistName"] as? String)?.trimmingCharacters(in: .whitespaces) ?? ""
            return MusicTrack(title: title, artist: artist, url: url)
        }
    }

    // MARK: - Helpers

    private static func url(_ base: String, _ items: [(String, String)]) -> URL? {
        var components = URLComponents(string: base)
        components?.queryItems = items.map { URLQueryItem(name: $0.0, value: $0.1) }
        return components?.url
    }

    private static func json(_ data: Data) -> Any? {
        try? JSONSerialization.jsonObject(with: data)
    }

    private static func path(_ value: Any?, _ keys: String...) -> Any? {
        keys.reduce(value) { current, key in (current as? [String: Any])?[key] }
    }

    private static func list(_ value: Any?) -> [Any] {
        value as? [Any] ?? []
    }

    /// "runs" pieces joined, or a "simpleText"; nil when empty.
    private static func runs(_ text: Any?) -> String? {
        let joined = (path(text, "simpleText") as? String)
            ?? list(path(text, "runs")).compactMap { path($0, "text") as? String }.joined()
        let trimmed = joined.trimmingCharacters(in: .whitespaces)
        return trimmed.isEmpty ? nil : trimmed
    }

    /// The runs that link to an artist's page; else the column's first run.
    private static func artists(_ column: Any?) -> String {
        let pieces = list(path(column, "musicResponsiveListItemFlexColumnRenderer", "text", "runs"))
        let named = pieces.filter {
            path($0, "navigationEndpoint", "browseEndpoint", "browseEndpointContextSupportedConfigs",
                 "browseEndpointContextMusicConfig", "pageType") as? String == artistPage
        }.compactMap { (path($0, "text") as? String)?.trimmingCharacters(in: .whitespaces) }.filter { !$0.isEmpty }
        if !named.isEmpty { return named.joined(separator: ", ") }
        return (pieces.first.flatMap { path($0, "text") as? String } ?? "").trimmingCharacters(in: .whitespaces)
    }

    /// JSON's true and false also read as the numbers 1 and 0.
    private static func integer(_ value: Any?) -> Int? {
        guard let number = value as? NSNumber, CFGetTypeID(number) != CFBooleanGetTypeID() else { return nil }
        return number as? Int
    }

    private static func videoID(_ value: Any?) -> String? {
        guard let id = value as? String, id.count == videoIDLength,
              id.unicodeScalars.allSatisfy(videoIDCharacters.contains) else { return nil }
        return id
    }
}
