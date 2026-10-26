import Foundation
import Testing
@testable import AsistanCore

@Suite("Music search")
struct MusicSearchTests {
    private func video(_ id: String, _ title: String, owner: String = "Kanal", extra: String = "") -> String {
        #"{"videoRenderer":{"videoId":"\#(id)","title":{"runs":[{"text":"\#(title)"}]},"ownerText":{"runs":[{"text":"\#(owner)"}]}\#(extra)}}"#
    }

    private func searchAnswer(_ items: [String]) -> Data {
        Data(#"{"contents":{"twoColumnSearchResultsRenderer":{"primaryContents":{"sectionListRenderer":{"contents":[{"itemSectionRenderer":{"contents":[\#(items.joined(separator: ","))]}}]}}}}}"#.utf8)
    }

    @Test("the first videos of a YouTube search, with their watch pages")
    func youTubeVideos() throws {
        let tarkan = MusicSearch.youTubeVideos(MusicFixtures.youTubeTarkan)
        let first = try #require(tarkan.first)
        #expect(first == MusicTrack(title: "TARKAN - Kış Güneşi", artist: "", url: URL(string: "https://www.youtube.com/watch?v=-CxauCeQ_SQ")!))
        #expect(first.spoken == "TARKAN - Kış Güneşi")
        let kuzu = MusicSearch.youTubeVideos(MusicFixtures.youTubeKuzuKuzu)
        #expect(kuzu.prefix(2).map(\.url.absoluteString) == [
            "https://www.youtube.com/watch?v=NAHRpEqgcL4", "https://www.youtube.com/watch?v=_xgryOIbJj4",
        ])
        #expect(kuzu[1].spoken == "Tarkan – Kuzu Kuzu")
    }

    @Test("shorts, premieres, ads, channels, playlists and bad ids are passed over")
    func youTubeSkips() {
        let answer = searchAnswer([
            #"{"adSlotRenderer":{}}"#, #"{"channelRenderer":{"channelId":"UC1"}}"#, #"{"playlistRenderer":{"playlistId":"PL1"}}"#,
            video("AAAAAAAAAAA", "Kısa", extra: #","navigationEndpoint":{"reelWatchEndpoint":{"videoId":"AAAAAAAAAAA"}}"#),
            video("BBBBBBBBBBB", "Yakında", extra: #","upcomingEventData":{"startTime":"1"}"#),
            video("not-an-id", "Bozuk"),
            video("CCCCCCCCCCC", "Sezen Aksu - Gidiyorum (Official Audio)", owner: "Sezen Aksu - Topic"),
        ])
        #expect(MusicSearch.youTubeVideos(answer) == [
            MusicTrack(title: "Sezen Aksu - Gidiyorum", artist: "", url: URL(string: "https://www.youtube.com/watch?v=CCCCCCCCCCC")!),
        ])
    }

    @Test("odd answers give nothing", arguments: ["null", "[]", #"{"contents":"x"}"#, "not json"])
    func oddAnswers(answer: String) {
        #expect(MusicSearch.youTubeVideos(Data(answer.utf8)).isEmpty)
        #expect(MusicSearch.youTubeMusicSongs(Data(answer.utf8)).isEmpty)
        #expect(MusicSearch.deezerTracks(Data(answer.utf8)).isEmpty)
        #expect(MusicSearch.iTunesSongs(Data(answer.utf8)).isEmpty)
    }

    @Test("the songs of a YouTube Music search, with their artists")
    func youTubeMusicSongs() throws {
        let first = try #require(MusicSearch.youTubeMusicSongs(MusicFixtures.youTubeMusicSezenAksu).first)
        #expect(first == MusicTrack(title: "Begonvil", artist: "Sezen Aksu", url: URL(string: "https://music.youtube.com/watch?v=tAT2nh_Smx0")!))
        #expect(first.spoken == "Sezen Aksu – Begonvil")
    }

    @Test("a YouTube video moves to YouTube Music")
    func onYouTubeMusic() {
        let video = MusicTrack(title: "Kuzu Kuzu", artist: "Tarkan", url: URL(string: "https://www.youtube.com/watch?v=NAHRpEqgcL4")!)
        #expect(MusicSearch.onYouTubeMusic(video).url.absoluteString == "https://music.youtube.com/watch?v=NAHRpEqgcL4")
    }

    @Test("Deezer tracks that can be played, and their page in the app")
    func deezer() throws {
        let first = try #require(MusicSearch.deezerTracks(MusicFixtures.deezerKuzuKuzu).first)
        #expect(first == MusicTrack(title: "Kuzu Kuzu", artist: "Tarkan", url: URL(string: "https://www.deezer.com/track/16412320")!))
        #expect(MusicSearch.appURL(first.url, scheme: "deezer")?.absoluteString == "deezer://www.deezer.com/track/16412320")
        let odd = Data(#"{"data":[{"id":1,"title":"Kilitli","readable":false},{"id":"2","title":"Metin"},{"id":true,"title":"Doğru"},{"type":"album","id":3,"title":"Albüm"},"x"]}"#.utf8)
        #expect(MusicSearch.deezerTracks(odd).isEmpty)
    }

    @Test("Apple Music songs from the iTunes search, only on Apple's own https pages")
    func iTunes() throws {
        let first = try #require(MusicSearch.iTunesSongs(MusicFixtures.iTunesKuzuKuzu).first)
        #expect(first.spoken == "Tarkan – Kuzu Kuzu")
        #expect(first.url.absoluteString.hasPrefix("https://music.apple.com/tr/album/kuzu-kuzu/499333901?i=499334149"))
        #expect(MusicSearch.appURL(first.url, scheme: "music")?.absoluteString.hasPrefix("music://music.apple.com/tr/album/") == true)
        let elsewhere = Data(#"{"results":[{"kind":"song","trackName":"X","trackViewUrl":"https://evil.example/x"},{"kind":"song","trackName":"Y","trackViewUrl":"http://music.apple.com/y"},{"kind":"music-video","trackName":"Z","trackViewUrl":"https://music.apple.com/z"}]}"#.utf8)
        #expect(MusicSearch.iTunesSongs(elsewhere).isEmpty)
    }

    @Test("search addresses and bodies carry the query")
    func requests() throws {
        let deezer = try #require(MusicSearch.deezerSearchURL("Kuzu & Kuzu"))
        #expect(URLComponents(url: deezer, resolvingAgainstBaseURL: false)?.queryItems?.first { $0.name == "q" }?.value == "Kuzu & Kuzu")
        let iTunes = try #require(MusicSearch.iTunesSearchURL("Şımarık", country: "TR"))
        let items = URLComponents(url: iTunes, resolvingAgainstBaseURL: false)?.queryItems ?? []
        #expect(items.contains(URLQueryItem(name: "term", value: "Şımarık")))
        #expect(items.contains(URLQueryItem(name: "entity", value: "song")))
        #expect(items.contains(URLQueryItem(name: "country", value: "tr")))
        let music = try #require(JSONSerialization.jsonObject(with: MusicSearch.youTubeSearchBody(
            "Tarkan", client: .music, language: "tr", country: "tr")) as? [String: Any])
        let client = (music["context"] as? [String: Any])?["client"] as? [String: Any]
        #expect(client?["gl"] as? String == "TR")
        #expect(client?["clientName"] as? String == "WEB_REMIX")
        #expect(music["query"] as? String == "Tarkan" && music["params"] != nil)
        let web = try #require(JSONSerialization.jsonObject(with: MusicSearch.youTubeSearchBody(
            "Tarkan", client: .web, language: "tr", country: "tr")) as? [String: Any])
        #expect(web["params"] == nil)
    }

    @Test("each service's search page", arguments: [
        (MusicService.youTube, "https://www.youtube.com/results?search_query=Sezen%20Aksu"),
        (.youTubeMusic, "https://music.youtube.com/search?q=Sezen%20Aksu"),
        (.deezer, "https://www.deezer.com/search/Sezen%20Aksu"),
        (.appleMusic, "https://music.apple.com/tr/search?term=Sezen%20Aksu"),
        (.spotify, "https://open.spotify.com/search/Sezen%20Aksu"),
    ])
    func searchPage(service: MusicService, page: String) {
        #expect(MusicSearch.searchPage(service, query: "Sezen Aksu", country: "TR")?.absoluteString == page)
    }

    @Test("Spotify's own search, every letter outside ASCII encoded")
    func spotify() {
        #expect(MusicSearch.spotifySearch("Tarkan Şımarık")?.absoluteString == "spotify:search:Tarkan%20%C5%9E%C4%B1mar%C4%B1k")
    }
}
