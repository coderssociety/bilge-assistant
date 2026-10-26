import Foundation
import Testing
@testable import AsistanCore

@Suite("Podcasts")
struct PodcastTests {
    /// Trimmed from the iTunes Search API (media=podcast, country=tr), plus results it may give without a feed.
    private let search = Data("""
    {"resultCount":5,"results":[
     {"collectionName":"Felsefe Hakkında Hiçbir Şey Bilmiyorum","artistName":"Ayşen İrem Ateş","feedUrl":"https://anchor.fm/s/103f33140/podcast/rss"},
     {"collectionName":"Medyascope Podcast","artistName":"Poddict: Medyascope","feedUrl":"https://feeds.megaphone.fm/medyascope"},
     {"collectionName":"Mesele Ekonomi","artistName":"Mesele Ekonomi","feedUrl":"https://media.rss.com/mesele-ekonomi/feed.xml"},
     {"collectionName":"Feedsiz Podcast","artistName":"Biri"},
     {"collectionName":"Eski Şema","feedUrl":"ftp://example.org/feed"}]}
    """.utf8)

    @Test("search results without an http(s) feed are dropped")
    func shows() {
        let shows = PodcastSearch.shows(from: search)
        #expect(shows.map(\.name) == ["Felsefe Hakkında Hiçbir Şey Bilmiyorum", "Medyascope Podcast", "Mesele Ekonomi"])
        #expect(PodcastSearch.shows(from: Data("{}".utf8)).isEmpty)
        #expect(PodcastSearch.shows(from: Data("bozuk".utf8)).isEmpty)
    }

    @Test("the podcast named is chosen, and nothing when none matches", arguments: [
        ("mesele ekonomi", "Mesele Ekonomi"), ("Medyascope", "Medyascope Podcast"), ("bilmiyorum", "Felsefe Hakkında Hiçbir Şey Bilmiyorum"),
        ("İrem Ateş", "Felsefe Hakkında Hiçbir Şey Bilmiyorum"), ("Serial", nil),
    ])
    func choice(query: String, expected: String?) {
        #expect(PodcastSearch.best(PodcastSearch.shows(from: search), for: query)?.name == expected)
    }

    @Test("the newest episode with audio is played")
    func latest() {
        let date = { ISO8601DateFormatter().date(from: $0) }
        let items: [RSSHeadlines.Item] = [
            .init(title: "Fragman", link: nil, enclosure: nil, published: date("2026-10-25T08:00:00Z")),
            .init(title: "Eski", link: nil, enclosure: URL(string: "https://example.org/1.mp3"), published: date("2026-10-20T08:00:00Z")),
            .init(title: "Yeni", link: nil, enclosure: URL(string: "https://example.org/2.mp3"), published: date("2026-10-24T08:00:00Z")),
        ]
        #expect(PodcastEpisodes.latest(items)?.title == "Yeni")
        let undated = [RSSHeadlines.Item(title: "İlk", link: nil, enclosure: URL(string: "https://example.org/a.mp3")),
                       RSSHeadlines.Item(title: "İkinci", link: nil, enclosure: URL(string: "https://example.org/b.mp3"))]
        #expect(PodcastEpisodes.latest(undated)?.title == "İlk")
        #expect(PodcastEpisodes.latest([RSSHeadlines.Item(title: "Yazı", link: nil)]) == nil)
    }

    @Test("an oldest-first feed cut off at the limit is read further for its newest episode")
    func oldestFirst() throws {
        let episodes = (1...5).map { day in
            "<item><title>Bölüm \(day)</title><pubDate>Mon, 0\(day) Sep 2025 06:00:00 +0000</pubDate>"
                + "<enclosure url=\"https://example.org/\(day).mp3\" type=\"audio/mpeg\"/></item>"
        }
        let ascending = Data("<rss><channel>\(episodes.joined())</channel></rss>".utf8)
        let start = RSSHeadlines.items(ascending, limit: 2)
        #expect(PodcastEpisodes.latest(start)?.title == "Bölüm 2")
        #expect(PodcastEpisodes.mayContinueWithNewer(start, itemLimit: 2, bytesRead: ascending.count, byteLimit: 1_000_000))
        #expect(PodcastEpisodes.mayContinueWithNewer(start, itemLimit: 60, bytesRead: 1_000_000, byteLimit: 1_000_000))
        #expect(PodcastEpisodes.latest(RSSHeadlines.items(ascending, limit: .max))?.title == "Bölüm 5")

        let descending = Data("<rss><channel>\(episodes.reversed().joined())</channel></rss>".utf8)
        let newestFirst = RSSHeadlines.items(descending, limit: 2)
        #expect(PodcastEpisodes.latest(newestFirst)?.title == "Bölüm 5")
        #expect(!PodcastEpisodes.mayContinueWithNewer(newestFirst, itemLimit: 2, bytesRead: descending.count, byteLimit: 1_000_000))
        let whole = RSSHeadlines.items(ascending, limit: 60)
        #expect(!PodcastEpisodes.mayContinueWithNewer(whole, itemLimit: 60, bytesRead: ascending.count, byteLimit: 1_000_000))
    }

    @Test("days since an episode came out count calendar days")
    func days() throws {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = try #require(TimeZone(identifier: "Europe/Istanbul"))
        let now = try #require(ISO8601DateFormatter().date(from: "2026-10-25T09:00:00Z"))
        let lateYesterday = try #require(ISO8601DateFormatter().date(from: "2026-10-24T20:00:00Z"))
        #expect(PodcastEpisodes.daysSince(lateYesterday, now: now, calendar: calendar) == 1)
        #expect(PodcastEpisodes.daysSince(now, now: now, calendar: calendar) == 0)
        #expect(PodcastEpisodes.daysSince(now.addingTimeInterval(86_400 * 12), now: now, calendar: calendar) == 0)
    }

    @Test("Turkish podcast requests", arguments: [
        ("Mesele Ekonomi podcastinin son bölümünü aç", PodcastCommand.playLatest(show: "Mesele Ekonomi")),
        ("Medyascope podcast'inin son bölümünü çalar mısın", .playLatest(show: "Medyascope")),
        ("Mesele Ekonomi podcastini aç", .playLatest(show: "Mesele Ekonomi")),
        ("Medyascope'un en son bölümünü aç", .playLatest(show: "Medyascope")),
        ("Medyascope'un yeni bölümü var mı", .checkNew(show: "Medyascope")),
        ("Mesele Ekonomi podcastinde yeni bölüm var mı", .checkNew(show: "Mesele Ekonomi")),
        ("Kısa Dalga'nın son bölümü ne zaman çıktı", .checkNew(show: "Kısa Dalga")),
    ])
    func turkish(command: String, expected: PodcastCommand) {
        #expect(PodcastRequest.parse(command) == expected)
    }

    @Test("other requests are left alone", arguments: [
        "podcast'i durdur", "son bölümü aç", "Kurtlar Vadisi dizisinin son bölümünü aç", "raporun son bölümünü oku",
        "raporun son bölümünde ne var", "bu kitabın son bölümünü özetle", "Power FM aç", "Tarkan çal", "podcast nedir",
    ])
    func notPodcast(command: String) {
        #expect(PodcastRequest.parse(command) == nil)
    }

    @Test("English podcast requests", arguments: [
        ("play the latest episode of The Daily", PodcastCommand.playLatest(show: "The Daily")),
        ("play the Lex Fridman podcast", .playLatest(show: "Lex Fridman")),
        ("is there a new episode of Huberman Lab", .checkNew(show: "Huberman Lab")),
        ("does Lex Fridman have a new episode", .checkNew(show: "Lex Fridman")),
        ("has Huberman Lab released a new episode", .checkNew(show: "Huberman Lab")),
    ])
    func english(command: String, expected: PodcastCommand) {
        #expect(PodcastRequest.parse(command, language: .english) == expected)
    }

    @Test("English requests for other tools", arguments: ["play some Queen", "play Power FM", "pause the podcast", "next episode"])
    func englishNotPodcast(command: String) {
        #expect(PodcastRequest.parse(command, language: .english) == nil)
    }

    @Test("pausing, resuming and seeking a podcast are media commands", arguments: [
        ("podcast'i durdur", QuickIntent.media(.pause, subject: .stream)), ("podcaste devam et", .media(.play, subject: .stream)),
        ("podcasti devam ettir", .media(.play, subject: .stream)), ("podcast'i aç", .media(.play, subject: .stream)),
        ("podcast'i 30 saniye ileri sar", .media(.seekForward(30), subject: .stream)),
        ("bölümü bir dakika geri sar", .media(.seekBackward(60), subject: .stream)),
    ])
    func controls(command: String, expected: QuickIntent) {
        #expect(QuickIntentParser.parse(TurkishNumberParser.digitize(command)) == expected)
    }
}
