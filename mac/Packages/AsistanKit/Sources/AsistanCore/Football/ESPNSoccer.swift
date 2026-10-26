import Foundation

public struct SoccerMatch: Sendable, Equatable {
    public enum State: Sendable, Equatable {
        case scheduled, live, halftime, finished, postponed
    }

    public struct Side: Sendable, Equatable {
        public let espnName: String
        public let score: Int?

        public init(espnName: String, score: Int?) {
            self.espnName = espnName
            self.score = score
        }
    }

    public let id: String
    public let kickoff: Date
    public let state: State
    /// ESPN's match clock while it is played: "67'", "90'+3'".
    public let clock: String?
    public let home: Side
    public let away: Side

    public init(id: String, kickoff: Date, state: State, clock: String?, home: Side, away: Side) {
        self.id = id
        self.kickoff = kickoff
        self.state = state
        self.clock = clock
        self.home = home
        self.away = away
    }

    public func involves(_ team: FootballTeam) -> Bool {
        [home, away].contains { SuperLigTeams.team(espnName: $0.espnName) == team }
    }
}

public struct SoccerScoreboard: Sendable, Equatable {
    public let matches: [SoccerMatch]
    /// The league's match days, "20261024".
    public let matchDays: [String]
}

public struct StandingRow: Sendable, Equatable {
    public let rank: Int
    public let espnName: String
    public let played: Int
    public let points: Int
}

/// ESPN's public soccer API for the Süper Lig (tur.1): the scoreboard for a day and the standings.
public enum ESPNSoccer {
    private struct ScoreboardJSON: Decodable {
        struct League: Decodable { let calendar: [String]? }
        struct Event: Decodable {
            let id: String
            let date: String
            let competitions: [Competition]
            let status: Status?
        }
        struct Competition: Decodable {
            let competitors: [Competitor]
            let status: Status?
        }
        struct Competitor: Decodable {
            let homeAway: String
            let score: String?
            let team: Team
        }
        struct Team: Decodable { let displayName: String }
        struct Status: Decodable {
            struct Kind: Decodable { let name: String?; let state: String?; let completed: Bool? }
            let displayClock: String?
            let type: Kind
        }

        let events: [Event]
        let leagues: [League]?

        enum CodingKeys: String, CodingKey { case events, leagues }

        init(from decoder: any Decoder) throws {
            let container = try decoder.container(keyedBy: CodingKeys.self)
            events = try container.decode([Lossy<Event>].self, forKey: .events).compactMap(\.value)
            // Other leagues list match days as objects; only the plain form is used.
            leagues = try? container.decode([League].self, forKey: .leagues)
        }
    }

    private struct StandingsJSON: Decodable {
        struct Child: Decodable { let standings: Standings }
        struct Standings: Decodable { let entries: [Entry] }
        struct Entry: Decodable {
            struct Team: Decodable { let displayName: String }
            struct Stat: Decodable { let name: String?; let value: Double? }
            let team: Team
            let stats: [Lossy<Stat>]
        }
        let children: [Child]
    }

    /// Skips one malformed element instead of failing the whole list.
    private struct Lossy<T: Decodable>: Decodable {
        let value: T?
        init(from decoder: any Decoder) throws { value = try? T(from: decoder) }
    }

    public static func scoreboard(_ data: Data) throws -> SoccerScoreboard {
        let json = try JSONDecoder().decode(ScoreboardJSON.self, from: data)
        let days = json.leagues?.first?.calendar?.compactMap(dayKey) ?? []
        return SoccerScoreboard(matches: json.events.compactMap(match).sorted { $0.kickoff < $1.kickoff },
                                matchDays: Array(Set(days)).sorted())
    }

    public static func standings(_ data: Data) throws -> [StandingRow] {
        let json = try JSONDecoder().decode(StandingsJSON.self, from: data)
        let entries = json.children.first?.standings.entries ?? []
        let rows = entries.map { entry -> StandingRow in
            let stats = entry.stats.compactMap(\.value)
            let stat = { (name: String) -> Int in Int(stats.first { $0.name == name }?.value ?? 0) }
            return StandingRow(rank: stat("rank"), espnName: entry.team.displayName, played: stat("gamesPlayed"),
                               points: stat("points"))
        }
        return rows.sorted { sortRank($0) < sortRank($1) }
    }

    /// A row without a rank goes last.
    private static func sortRank(_ row: StandingRow) -> Int {
        row.rank == 0 ? Int.max : row.rank
    }

    /// "2026-10-23T07:00Z" → "20261023".
    static func dayKey(_ calendarEntry: String) -> String? {
        let digits = calendarEntry.prefix(10).filter(\.isNumber)
        return digits.count == 8 ? String(digits) : nil
    }

    /// The match days of the round being played, or of the next one: days follow each other within a round
    /// (Friday to Monday), and a gap of more than a day starts the next.
    public static func roundDays(matchDays: [String], today: String) -> [String] {
        var rounds: [[String]] = []
        for day in matchDays.sorted() {
            if let last = rounds.last?.last, let gap = daysBetween(last, day), gap <= 1 {
                rounds[rounds.count - 1].append(day)
            } else {
                rounds.append([day])
            }
        }
        return rounds.first { ($0.last ?? "") >= today } ?? rounds.last ?? []
    }

    private static func daysBetween(_ first: String, _ second: String) -> Int? {
        guard let start = date(fromKey: first), let end = date(fromKey: second) else { return nil }
        return Int((end.timeIntervalSince(start) / 86_400).rounded())
    }

    static func date(fromKey key: String) -> Date? {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = .gmt
        formatter.dateFormat = "yyyyMMdd"
        return formatter.date(from: key)
    }

    private static func match(_ event: ScoreboardJSON.Event) -> SoccerMatch? {
        guard let competition = event.competitions.first, let kickoff = kickoffDate(event.date),
              let home = competition.competitors.first(where: { $0.homeAway == "home" }),
              let away = competition.competitors.first(where: { $0.homeAway == "away" }),
              let status = competition.status ?? event.status else { return nil }
        let state = state(status)
        let hasScore = state != .scheduled && state != .postponed
        return SoccerMatch(
            id: event.id, kickoff: kickoff, state: state, clock: status.displayClock,
            home: .init(espnName: home.team.displayName, score: hasScore ? home.score.flatMap { Int($0) } : nil),
            away: .init(espnName: away.team.displayName, score: hasScore ? away.score.flatMap { Int($0) } : nil))
    }

    private static func state(_ status: ScoreboardJSON.Status) -> SoccerMatch.State {
        let name = status.type.name ?? ""
        if ["POSTPONED", "CANCELED", "CANCELLED", "SUSPENDED", "ABANDONED", "DELAYED"].contains(where: name.contains) {
            return .postponed
        }
        if name.contains("HALFTIME") { return .halftime }
        switch status.type.state {
        case "in": return .live
        case "post": return status.type.completed == false ? .postponed : .finished
        default: return .scheduled
        }
    }

    /// "2026-10-25T16:00Z", with or without seconds.
    private static func kickoffDate(_ text: String) -> Date? {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = .gmt
        for format in ["yyyy-MM-dd'T'HH:mm'Z'", "yyyy-MM-dd'T'HH:mm:ss'Z'"] {
            formatter.dateFormat = format
            if let date = formatter.date(from: text) { return date }
        }
        return nil
    }
}
