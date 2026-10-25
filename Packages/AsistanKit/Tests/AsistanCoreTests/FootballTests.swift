import Foundation
import Testing
@testable import AsistanCore

@Suite("Football")
struct FootballTests {
    /// Trimmed from ESPN's live tur.1 scoreboard: a finished match, one at half-time and one to come.
    private let scoreboard = """
    {"leagues":[{"calendar":["2026-10-23T07:00Z","2026-10-24T07:00Z","2026-10-25T07:00Z","2026-10-26T07:00Z",\
    "2026-10-30T07:00Z","2026-10-31T07:00Z","2026-11-01T07:00Z","2026-11-02T08:00Z"]}],
    "events":[
    {"id":"1","date":"2026-10-25T13:00Z","status":{"displayClock":"90'+5'","type":{"name":"STATUS_FULL_TIME","state":"post","completed":true}},
     "competitions":[{"competitors":[{"homeAway":"home","score":"2","team":{"displayName":"Konyaspor"}},
                                     {"homeAway":"away","score":"0","team":{"displayName":"Genclerbirligi"}}]}]},
    {"id":"2","date":"2026-10-25T16:00Z","status":{"displayClock":"45'+6'","type":{"name":"STATUS_HALFTIME","state":"in","completed":false}},
     "competitions":[{"competitors":[{"homeAway":"home","score":"2","team":{"displayName":"Goztepe"}},
                                     {"homeAway":"away","score":"0","team":{"displayName":"Çorum FK"}}]}]},
    {"id":"3","date":"2026-10-26T18:30Z","status":{"displayClock":"0'","type":{"name":"STATUS_SCHEDULED","state":"pre","completed":false}},
     "competitions":[{"competitors":[{"homeAway":"home","score":"0","team":{"displayName":"Galatasaray"}},
                                     {"homeAway":"away","score":"0","team":{"displayName":"Fenerbahce"}}]}]},
    {"id":"4","date":"bozuk","competitions":[]}
    ]}
    """

    private let standings = """
    {"children":[{"standings":{"entries":[
    {"team":{"displayName":"Galatasaray"},"stats":[{"name":"gamesPlayed","value":8.0},{"name":"points","value":19.0},{"name":"rank","value":2.0},{"name":"overall","value":null}]},
    {"team":{"displayName":"Amed SFK"},"stats":[{"name":"gamesPlayed","value":9.0},{"name":"points","value":20.0},{"name":"rank","value":1.0}]},
    {"team":{"displayName":"Fenerbahce"},"stats":[{"name":"gamesPlayed","value":8.0},{"name":"points","value":16.0},{"name":"rank","value":3.0}]}
    ]}}]}
    """

    private var calendar: Calendar {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "Europe/Istanbul")!
        return calendar
    }

    /// Sunday 25 October 2026, 19:50 in Istanbul.
    private let now = ISO8601DateFormatter().date(from: "2026-10-25T16:50:00Z")!

    @Test("team names and nicknames", arguments: [
        ("Galatasaray maçı kaç kaç", "Galatasaray"), ("GS'nin maçı ne zaman", "Galatasaray"), ("Cimbom kazandı mı", "Galatasaray"),
        ("Fenerbahçe ne zaman oynuyor", "Fenerbahçe"), ("FB maçı", "Fenerbahçe"), ("Fener'in maçı", "Fenerbahçe"),
        ("BJK skor", "Beşiktaş"), ("TS kaç kaç", "Trabzonspor"), ("Başakşehir'in maçı", "Başakşehir"),
        ("Adana Demirspor kazandı mı", "Adana Demirspor"), ("when do Fenerbahce play", "Fenerbahçe"),
    ])
    func teams(text: String, expected: String) {
        #expect(SuperLigTeams.named(in: text)?.name == expected)
    }

    @Test("ESPN names map to Turkish spellings")
    func espnNames() {
        #expect(SuperLigTeams.spokenName(espnName: "Istanbul Basaksehir") == "Başakşehir")
        #expect(SuperLigTeams.spokenName(espnName: "Amed SFK") == "Amedspor")
        #expect(SuperLigTeams.spokenName(espnName: "Some New Club") == "Some New Club")
    }

    @Test("what the question asks")
    func queries() {
        #expect(FootballRequest.query("Galatasaray maçı kaç kaç").kind == .teamMatch)
        #expect(FootballRequest.query("Fenerbahçe ne zaman oynuyor").kind == .nextMatch)
        #expect(FootballRequest.query("Beşiktaş'ın sıradaki maçı").kind == .nextMatch)
        #expect(FootballRequest.query("puan durumu").kind == .standings)
        #expect(FootballRequest.query("Galatasaray kaçıncı sırada").kind == .standings)
        #expect(FootballRequest.query("bu hafta Süper Lig maçları") == FootballQuery(team: nil, kind: .fixtures, day: .round))
        #expect(FootballRequest.query("dün maç sonuçları").day == .yesterday)
        #expect(FootballRequest.query("maç sonuçları").day == .latest)
        #expect(FootballRequest.query("what's the Super Lig table", language: .english).kind == .standings)
        #expect(FootballRequest.query("when do Galatasaray play next", language: .english).kind == .nextMatch)
    }

    @Test("the scoreboard, a broken event skipped")
    func parsesScoreboard() throws {
        let board = try ESPNSoccer.scoreboard(Data(scoreboard.utf8))
        #expect(board.matches.map(\.id) == ["1", "2", "3"])
        #expect(board.matches.map(\.state) == [.finished, .halftime, .scheduled])
        #expect(board.matches[0].home.score == 2 && board.matches[0].away.score == 0)
        #expect(board.matches[2].home.score == nil)
        #expect(board.matchDays.first == "20261023" && board.matchDays.count == 8)
    }

    @Test("the round being played, then the next one")
    func rounds() {
        let days = ["20261023", "20261024", "20261025", "20261026", "20261030", "20261031", "20261101", "20261102"]
        #expect(ESPNSoccer.roundDays(matchDays: days, today: "20261025") == Array(days.prefix(4)))
        #expect(ESPNSoccer.roundDays(matchDays: days, today: "20261028") == Array(days.suffix(4)))
        #expect(ESPNSoccer.roundDays(matchDays: days, today: "20261201") == Array(days.suffix(4)))
    }

    @Test("standings sorted by rank")
    func parsesStandings() throws {
        let rows = try ESPNSoccer.standings(Data(standings.utf8))
        #expect(rows.map(\.rank) == [1, 2, 3])
        #expect(rows[1] == StandingRow(rank: 2, espnName: "Galatasaray", played: 8, points: 19))
    }

    @Test("matches as spoken in Turkish")
    func turkishMatches() throws {
        let board = try ESPNSoccer.scoreboard(Data(scoreboard.utf8))
        let report = FootballReport(now: now, calendar: calendar, language: .turkish)
        #expect(report.match(board.matches[0]) == "Bugün oynanan maçta Konyaspor 2, Gençlerbirliği 0.")
        #expect(report.match(board.matches[1]) == "Göztepe Çorum FK maçında devre arası: Göztepe 2, Çorum FK 0.")
        #expect(report.match(board.matches[2]) == "Galatasaray Fenerbahçe maçı yarın 21:30'da.")
        let live = SoccerMatch(id: "5", kickoff: now, state: .live, clock: "90'+3'", home: .init(espnName: "Besiktas", score: 1),
                               away: .init(espnName: "Trabzonspor", score: 1))
        #expect(report.match(live) == "Beşiktaş Trabzonspor maçı oynanıyor, dakika 90 artı 3: Beşiktaş 1, Trabzonspor 1.")
    }

    @Test("matches as spoken in English")
    func englishMatches() throws {
        let board = try ESPNSoccer.scoreboard(Data(scoreboard.utf8))
        let report = FootballReport(now: now, calendar: calendar, language: .english)
        #expect(report.match(board.matches[0]) == "Full time today: Konyaspor 2, Gençlerbirliği 0.")
        #expect(report.match(board.matches[2]) == "Galatasaray v Fenerbahçe is tomorrow at 9:30\u{202F}PM.")
    }

    @Test("a day of fixtures and the table")
    func fixturesAndTable() throws {
        let board = try ESPNSoccer.scoreboard(Data(scoreboard.utf8))
        let report = FootballReport(now: now, calendar: calendar, language: .turkish)
        #expect(report.fixtures(Array(board.matches.prefix(2)), day: .today)
            == "Bugünkü Süper Lig maçları: Konyaspor 2, Gençlerbirliği 0; Göztepe 2, Çorum FK 0, devre arası.")
        #expect(report.fixtures([], day: .tomorrow) == "Yarın Süper Lig maçı yok.")
        let rows = try ESPNSoccer.standings(Data(standings.utf8))
        #expect(report.standings(rows, team: nil)
            == "Süper Lig puan durumu: lider Amedspor 20 puan, ikinci Galatasaray 19, üçüncü Fenerbahçe 16.")
        #expect(report.standings(rows, team: SuperLigTeams.named(in: "Galatasaray"))
            == "Galatasaray 8 maçta 19 puanla ikinci sırada. Lider Amedspor, 20 puan.")
        #expect(report.ordinal(14) == "on dördüncü")
    }
}
