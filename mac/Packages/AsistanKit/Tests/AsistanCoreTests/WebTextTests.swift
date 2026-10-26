import Foundation
import Testing
@testable import AsistanCore

@Suite("Web text")
struct WebTextTests {
    @Test("weather sentences")
    func weather() {
        #expect(WeatherReport.current(city: "İstanbul", temperature: 17.6, code: 2)
            == "İstanbul'da şu an hava parçalı bulutlu, 18 derece.")
        #expect(WeatherReport.daily(city: "Ankara", dayName: "yarın", minimum: 4.2, maximum: 12.5, code: 63, rainChance: 80)
            == "Ankara'da yarın hava yağmurlu, sıcaklık 4 ile 13 derece arasında. Yağış ihtimali yüzde 80.")
        #expect(!WeatherReport.daily(city: "İzmir", dayName: "bugün", minimum: 20, maximum: 28, code: 0, rainChance: 10)
            .contains("Yağış"))
    }

    @Test("page text drops scripts, styles and tags and decodes entities")
    func html() {
        let page = """
        <html><head><title>Haber &amp; Yorum</title><style>p{color:red}</style></head>
        <body><nav>Menü</nav><script>alert('x')</script><h1>Başlık</h1><p>Birinci&nbsp;paragraf &#8220;alıntı&#8221;.</p>
        <p>İkinci <b>kalın</b> paragraf.</p><footer>Telif</footer></body></html>
        """
        #expect(HTMLText.extract(page) == "Başlık\nBirinci paragraf “alıntı”.\nİkinci kalın paragraf.")
        #expect(HTMLText.title(page) == "Haber & Yorum")
    }

    @Test("RSS item titles, skipping the channel title")
    func rss() {
        let feed = """
        <?xml version="1.0"?><rss><channel><title>Kanal</title>
        <item><title><![CDATA[Birinci haber]]></title></item>
        <item><title>İkinci haber</title></item>
        <item><title>Üçüncü haber</title></item>
        </channel></rss>
        """
        #expect(RSSHeadlines.parse(Data(feed.utf8), limit: 2) == ["Birinci haber", "İkinci haber"])
    }

    @Test("RSS and Atom items keep their article address; other schemes are dropped")
    func links() {
        let rss = """
        <rss><channel><link>https://kanal.example</link>
        <item><title>Birinci</title><link>https://www.aa.com.tr/tr/haber/1</link></item>
        <item><title>İkinci</title><link>javascript:alert(1)</link></item>
        </channel></rss>
        """
        #expect(RSSHeadlines.items(Data(rss.utf8), limit: 5) == [
            .init(title: "Birinci", link: URL(string: "https://www.aa.com.tr/tr/haber/1")),
            .init(title: "İkinci", link: nil),
        ])
        let atom = """
        <feed><entry><title>Atom</title><link rel="alternate" href="https://example.org/a"/></entry></feed>
        """
        #expect(RSSHeadlines.items(Data(atom.utf8), limit: 5) == [.init(title: "Atom", link: URL(string: "https://example.org/a"))])
    }

    @Test("podcast items keep their audio enclosure and publication date")
    func enclosures() throws {
        let rss = """
        <rss xmlns:itunes="http://www.itunes.com/dtds/podcast-1.0.dtd"><channel><title>Mesele Ekonomi</title>
        <item><title><![CDATA[Piyasalar Allak Bullak!]]></title><itunes:title>Başka başlık</itunes:title>
        <enclosure url="https://content.rss.com/episodes/1.mp3" length="28321921" type="audio/mpeg"/>
        <pubDate>Sat, 24 Oct 2026 07:30:17 GMT</pubDate></item>
        <item><title>Kapak</title><enclosure url="https://example.org/kapak.jpg" type="image/jpeg"/>
        <pubDate>Fri, 23 Oct 2026 10:12:59 +0300</pubDate></item>
        <item><title>Eski</title><enclosure url="ftp://example.org/eski.mp3"/><pubDate>bozuk tarih</pubDate></item>
        </channel></rss>
        """
        let items = RSSHeadlines.items(Data(rss.utf8), limit: 5)
        #expect(items.map(\.title) == ["Piyasalar Allak Bullak!", "Kapak", "Eski"])
        #expect(items[0].enclosure == URL(string: "https://content.rss.com/episodes/1.mp3"))
        #expect(items[0].published == ISO8601DateFormatter().date(from: "2026-10-24T07:30:17Z"))
        #expect(items[1].enclosure == nil)
        #expect(items[1].published == ISO8601DateFormatter().date(from: "2026-10-23T07:12:59Z"))
        #expect(items[2].enclosure == nil && items[2].published == nil)

        let atom = """
        <feed><entry><title>Bölüm</title><link rel="enclosure" type="audio/mp4" href="https://example.org/b.m4a"/>
        <published>2026-10-20T08:00:00Z</published></entry></feed>
        """
        let entry = try #require(RSSHeadlines.items(Data(atom.utf8), limit: 5).first)
        #expect(entry.enclosure == URL(string: "https://example.org/b.m4a"))
        #expect(entry.published == ISO8601DateFormatter().date(from: "2026-10-20T08:00:00Z"))
    }

    @Test("a feed cut off midway still gives the items before the cut")
    func truncatedFeed() {
        let cut = """
        <rss><channel><item><title>Son bölüm</title><enclosure url="https://example.org/1.mp3" type="audio/mpeg"/></item>
        <item><title>Önceki bölüm</title><enclosure url="https://exa
        """
        #expect(RSSHeadlines.items(Data(cut.utf8), limit: 5).map(\.title) == ["Son bölüm"])
    }

    @Test("locative suffix follows vowel harmony and hard consonants", arguments: [
        ("İstanbul", "İstanbul'da"), ("Ankara", "Ankara'da"), ("İzmir", "İzmir'de"), ("Paris", "Paris'te"),
        ("Kars", "Kars'ta"), ("Berlin", "Berlin'de"), ("Tokyo", "Tokyo'da"), ("Muş", "Muş'ta"), ("Köln", "Köln'de"),
    ])
    func locative(name: String, expected: String) {
        #expect(TurkishGrammar.locative(name) == expected)
    }
}
