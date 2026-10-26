import Foundation
import Testing
@testable import AsistanCore

@Suite("Earthquakes")
struct EarthquakeTests {
    /// Trimmed from a live AFAD answer; the last event has numbers instead of strings and no id.
    private let afad = """
    [{"rms":"0.53","eventID":"597367","location":"Sındırgı (Balıkesir)","latitude":"39.23283","longitude":"28.08317",\
    "depth":"14.08","type":"ML","magnitude":"2.3","country":"Türkiye","province":"Balıkesir","district":"Sındırgı",\
    "neighborhood":"Kozlu","date":"2026-10-25T15:40:56","isEventUpdate":false,"lastUpdateDate":null},
    {"rms":"0.68","eventID":"597364","location":"Ege Denizi - Kuşadası Körfezi - [10.82 km] Menderes (İzmir)",\
    "latitude":"37.91883","longitude":"27.11517","depth":"7","type":"ML","magnitude":"4.6","country":null,\
    "province":"İzmir","district":"Menderes","neighborhood":null,"date":"2026-10-25T14:39:54","isEventUpdate":false},
    {"eventID":597000,"location":"Göksun (Kahramanmaraş)","latitude":38.01683,"longitude":36.60783,"depth":7.16,\
    "magnitude":1.5,"province":"Kahramanmaraş","date":"2026-10-24T14:56:13"},
    {"location":"Bozuk","latitude":"1","longitude":"2","magnitude":"3","date":"2026-10-24T14:56:13"}]
    """

    /// Trimmed from the live Kandilli page, header lines included.
    private let kandilli = """
    <pre>
    ..................TÜRKİYE VE YAKIN ÇEVRESİNDEKİ SON DEPREMLER....................
                                                            Büyüklük
    Tarih      Saat      Enlem(N)  Boylam(E) Derinlik(km)  MD   ML   Mw    Yer                                             Çözüm Niteliği
    ---------- --------  --------  -------   ----------    ------------    --------------                                  --------------
    2026.10.25 18:40:56  39.2415   28.0832       11.3      -.-  2.6  -.-   KOZLU-SINDIRGI (BALIKESIR)                        İlksel
    2026.10.25 17:18:58  34.5762   25.4058       11.2      -.-  2.5  -.-   GIRIT ADASI (AKDENIZ)                             İlksel
    2026.10.23 09:38:05  36.2343   33.8665       25.3      -.-  2.7  4.1   SILIFKE ACIKLARI-MERSIN (AKDENIZ)                 REVIZE02   (2026.10.23 09:38:05)
    </pre>
    """

    private let now = ISO8601DateFormatter().date(from: "2026-10-25T16:00:00Z")!

    @Test("AFAD events, with strings or numbers, and a broken one skipped")
    func parsesAFAD() throws {
        let quakes = try AFADEarthquakes.parse(Data(afad.utf8))
        #expect(quakes.count == 3)
        let first = try #require(quakes.first)
        #expect(first.id == "afad-597367")
        #expect(first.magnitude == 2.3)
        #expect(first.depthKm == 14.08)
        #expect(first.place == "Sındırgı, Balıkesir")
        #expect(first.date == ISO8601DateFormatter().date(from: "2026-10-25T15:40:56Z"))
        #expect(quakes[1].place == "Ege Denizi, Kuşadası Körfezi, Menderes, İzmir")
        #expect(quakes[2].id == "afad-597000")
        #expect(quakes[2].magnitude == 1.5)
    }

    @Test("an AFAD answer that is not a list is unreadable")
    func rejectsAFADError() {
        #expect(throws: EarthquakeFeedError.unreadable) { try AFADEarthquakes.parse(Data(#"{"error":"x"}"#.utf8)) }
    }

    @Test("Kandilli rows in windows-1254, local time, preferring Mw")
    func parsesKandilli() throws {
        let data = try #require(kandilli.data(using: .windowsCP1254))
        let quakes = KandilliEarthquakes.parse(KandilliEarthquakes.text(from: data))
        #expect(quakes.count == 3)
        let first = try #require(quakes.first)
        #expect(first.date == ISO8601DateFormatter().date(from: "2026-10-25T15:40:56Z"))
        #expect(first.magnitude == 2.6)
        #expect(first.depthKm == 11.3)
        #expect(first.place == "Kozlu-Sindirgi, Balıkesir")
        #expect(first.province == "Balıkesir")
        #expect(quakes[1].place == "Girit Adasi, Akdeniz")
        #expect(quakes[1].province == nil)
        #expect(quakes[2].magnitude == 4.1)
        #expect(quakes[2].id == "kandilli-20261023093805")
    }

    @Test("distance between province centres")
    func distance() throws {
        let istanbul = try #require(TurkishProvinces.find("İstanbul"))
        let ankara = try #require(TurkishProvinces.find("ankara"))
        #expect(abs(istanbul.centre.kilometres(to: ankara.centre) - 350) < 15)
        #expect(istanbul.centre.kilometres(to: istanbul.centre) == 0)
        #expect(TurkishProvinces.all.count == 81)
        #expect(Set(TurkishProvinces.all.map(\.name)).count == 81)
    }

    @Test("provinces named in requests", arguments: [
        ("İzmir'de deprem var mı", "İzmir"), ("Van'da deprem oldu mu", "Van"), ("Antep'te sarsıntı", "Gaziantep"),
        ("Kahramanmaraş depremi", "Kahramanmaraş"), ("earthquake in Izmir", "İzmir"), ("BALIKESIR", "Balıkesir"),
        ("Muş'ta deprem", "Muş"), ("Muş'un depremlerini söyler misin", "Muş"), ("muş deprem", "Muş"),
    ])
    func provinces(text: String, expected: String) {
        #expect(TurkishProvinces.named(in: text)?.name == expected)
    }

    @Test("no province in", arguments: [
        "son depremler", "deprem oldu mu", "bugün büyük deprem oldu mu", "en son deprem nerede",
        "son depremler nerede biliyor musun", "deprem oldu mu söyler müsün",
    ])
    func noProvince(text: String) {
        #expect(TurkishProvinces.named(in: text) == nil)
    }

    @Test("what the question asks")
    func queries() {
        #expect(EarthquakeRequest.query("en son deprem nerede").latestOnly)
        #expect(!EarthquakeRequest.query("son depremler").latestOnly)
        let big = EarthquakeRequest.query("bugün büyük deprem oldu mu")
        #expect(big.period == .today && big.minimumMagnitude == 4)
        #expect(EarthquakeRequest.query("5 üzeri deprem oldu mu").minimumMagnitude == 5)
        #expect(EarthquakeRequest.query("yakınımda deprem oldu mu").nearUser)
        #expect(EarthquakeRequest.query("İzmir'de deprem var mı").province?.name == "İzmir")
        let english = EarthquakeRequest.query("was there a big earthquake near me today", language: .english)
        #expect(english.nearUser && english.period == .today && english.minimumMagnitude == 4)
    }

    @Test("a province with nothing nearby says so")
    func nothingNearby() throws {
        let quakes = try AFADEarthquakes.parse(Data(afad.utf8))
        let query = EarthquakeQuery(province: TurkishProvinces.find("Van"))
        let text = EarthquakeReport(query: query, home: nil, source: .afad, now: now, language: .turkish).text(for: quakes)
        #expect(text == "Son 24 saatte Van ve çevresinde deprem kaydedilmedi.")
    }

    @Test("the latest event with its age, place, magnitude and depth")
    func latest() throws {
        let quakes = try AFADEarthquakes.parse(Data(afad.utf8))
        let report = EarthquakeReport(query: EarthquakeQuery(latestOnly: true), home: nil, source: .afad, now: now, language: .turkish)
        #expect(report.text(for: quakes) == "En son deprem: 19 dakika önce Sındırgı, Balıkesir merkezli 2,3 büyüklüğünde, derinlik 14 kilometre.")
        let english = EarthquakeReport(query: EarthquakeQuery(latestOnly: true), home: nil, source: .kandilli, now: now, language: .english)
        #expect(english.text(for: quakes)
            == "The latest earthquake was 19 minutes ago, magnitude 2.3 near Sındırgı, Balıkesir, 14 kilometers deep. Data from Kandilli Observatory.")
    }

    @Test("a country-wide summary counts felt earthquakes only")
    func summary() throws {
        let quakes = try AFADEarthquakes.parse(Data(afad.utf8))
        let report = EarthquakeReport(query: EarthquakeQuery(), home: nil, source: .afad, now: now, language: .turkish)
        #expect(report.text(for: quakes) == "Son 24 saatte 3 ve üzeri büyüklükte 1 deprem oldu. "
            + "1 saat 20 dakika önce Ege Denizi, Kuşadası Körfezi, Menderes, İzmir merkezli 4,6 büyüklüğünde, derinlik 7 kilometre.")
        let izmir = EarthquakeReport(query: EarthquakeQuery(province: TurkishProvinces.find("İzmir")), home: nil, source: .afad,
                                     now: now, language: .turkish)
        #expect(izmir.text(for: quakes).contains("İzmir merkezine 56 kilometre uzaklıkta"))
    }

    @Test("ages as spoken")
    func ages() {
        #expect(SpokenAge.text(since: now.addingTimeInterval(-20), now: now, language: .turkish) == "az önce")
        #expect(SpokenAge.text(since: now.addingTimeInterval(-5 * 3600), now: now, language: .turkish) == "5 saat önce")
        #expect(SpokenAge.text(since: now.addingTimeInterval(-60), now: now, language: .english) == "1 minute ago")
        #expect(SpokenAge.text(since: now.addingTimeInterval(-50 * 3600), now: now, language: .english) == "2 days ago")
    }
}
