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

    @Test("locative suffix follows vowel harmony and hard consonants", arguments: [
        ("İstanbul", "İstanbul'da"), ("Ankara", "Ankara'da"), ("İzmir", "İzmir'de"), ("Paris", "Paris'te"),
        ("Kars", "Kars'ta"), ("Berlin", "Berlin'de"), ("Tokyo", "Tokyo'da"), ("Muş", "Muş'ta"), ("Köln", "Köln'de"),
    ])
    func locative(name: String, expected: String) {
        #expect(TurkishGrammar.locative(name) == expected)
    }
}
