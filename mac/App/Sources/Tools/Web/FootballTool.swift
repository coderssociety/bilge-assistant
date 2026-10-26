import AsistanCore
import Foundation
import FoundationModels

/// ESPN's Süper Lig scoreboard (one day per request) and standings.
enum SuperLigFeed {
    typealias Board = FeedCache<SoccerScoreboard>.Entry

    private static let base = "https://site.api.espn.com/apis"
    private static let boards = FeedCache<SoccerScoreboard>()
    private static let table = FeedCache<[StandingRow]>()
    private static let liveFreshness: TimeInterval = 60
    private static let pastFreshness: TimeInterval = 60 * 60
    private static let futureFreshness: TimeInterval = 10 * 60
    private static let tableFreshness: TimeInterval = 10 * 60

    static func scoreboard(day: String, today: String) async throws -> Board {
        let maxAge = day == today ? liveFreshness : (day < today ? pastFreshness : futureFreshness)
        return try await boards.value(for: day, maxAge: maxAge) {
            var url = URLComponents(string: "\(base)/site/v2/sports/soccer/tur.1/scoreboard")!
            url.queryItems = [.init(name: "dates", value: day)]
            let data = try await WebFetch.data(from: url.url!)
            return try readable { try ESPNSoccer.scoreboard(data) }
        }
    }

    /// The days' scoreboards fetched at once; a day that fails is left out unless all of them do.
    static func scoreboards(days: [String], today: String) async throws -> [Board] {
        guard !days.isEmpty else { return [] }
        return try await withThrowingTaskGroup(of: Board?.self) { group in
            for day in days {
                group.addTask {
                    do {
                        return try await scoreboard(day: day, today: today)
                    } catch is CancellationError {
                        throw CancellationError()
                    } catch {
                        Log.tools.error("Scoreboard \(day, privacy: .public) failed: \(error.localizedDescription, privacy: .public)")
                        return nil
                    }
                }
            }
            var boards: [Board] = []
            for try await board in group {
                if let board { boards.append(board) }
            }
            guard !boards.isEmpty else { throw WebFetchError.unreachable }
            return boards
        }
    }

    static func standings() async throws -> FeedCache<[StandingRow]>.Entry {
        try await table.value(for: "tur.1", maxAge: tableFreshness) {
            let data = try await WebFetch.data(from: URL(string: "\(base)/v2/sports/soccer/tur.1/standings")!)
            return try readable { try ESPNSoccer.standings(data) }
        }
    }

    private static func readable<T>(_ parse: () throws -> T) throws -> T {
        do {
            return try parse()
        } catch {
            Log.tools.error("Unreadable ESPN answer: \(String(describing: error), privacy: .public)")
            throw WebFetchError.unreadable
        }
    }
}

/// "Galatasaray maçı kaç kaç", "Fenerbahçe ne zaman oynuyor", "puan durumu", "dün maç sonuçları".
/// Routed by rule (`RouteGuard.infoTopic`).
struct FootballTool: RuleRoutedTool {
    let name = "football"
    let description = "Süper Lig maç skorlarını, fikstürü ve puan durumunu söyler (ESPN)."
    /// Match days looked at before or after today for a team's last or next match.
    private static let searchedDays = 4

    @Generable
    struct Arguments {
        @Guide(description: "Kullanıcının isteği, olduğu gibi")
        var request: String
    }

    @MainActor
    func claims(_ command: String) -> Bool {
        RouteGuard.infoTopic(command, language: AppLanguage.current) == name
    }

    func arguments(fromCommand command: String) -> Arguments? {
        Arguments(request: command)
    }

    func call(arguments: Arguments) async throws -> String {
        let language = AppLanguage.current
        let query = FootballRequest.query(arguments.request, language: language)
        let now = Date.now
        let report = FootballReport(now: now, language: language)
        do {
            if query.kind == .standings {
                let entry = try await SuperLigFeed.standings()
                return entry.stalenessNote + report.standings(entry.value, team: query.team)
            }
            if let team = query.team, query.kind != .fixtures {
                return try await teamMatch(team, upcoming: query.kind == .nextMatch, now: now, report: report)
            }
            return try await fixtures(query.day, now: now, report: report)
        } catch {
            return ToolReply.failure(String(localized: "Süper Lig bilgisi alınamadı. \(error.localizedDescription)"))
        }
    }

    private func teamMatch(_ team: FootballTeam, upcoming: Bool, now: Date, report: FootballReport) async throws -> String {
        let today = Self.dayKey(now)
        let board = try await SuperLigFeed.scoreboard(day: today, today: today)
        if let match = board.value.matches.first(where: { $0.involves(team) }), !upcoming || match.state != .finished {
            return board.stalenessNote + report.match(match)
        }
        let days = upcoming
            ? Array(candidateDays(board.value.matchDays, now: now, forward: true).prefix(Self.searchedDays))
            : Array(candidateDays(board.value.matchDays, now: now, forward: false).suffix(Self.searchedDays))
        let boards = try await SuperLigFeed.scoreboards(days: days, today: today)
        let matches = boards.flatMap(\.value.matches).filter { $0.involves(team) }
        let found = upcoming
            ? matches.filter { $0.kickoff > now }.min { $0.kickoff < $1.kickoff }
            : matches.filter { $0.kickoff < now }.max { $0.kickoff < $1.kickoff }
        guard let found else { return report.noMatch(for: team, upcoming: upcoming) }
        return (boards.first(where: \.isStale)?.stalenessNote ?? "") + report.match(found)
    }

    private func fixtures(_ day: FootballQuery.Day, now: Date, report: FootballReport) async throws -> String {
        let today = Self.dayKey(now)
        let board = try await SuperLigFeed.scoreboard(day: today, today: today)
        let days: [String] = switch day {
        case .today: [today]
        case .yesterday: [Self.dayKey(now, adding: -1)]
        case .tomorrow: [Self.dayKey(now, adding: 1)]
        case .round: ESPNSoccer.roundDays(matchDays: board.value.matchDays, today: today)
        case .latest: board.value.matches.contains { $0.state == .finished }
            ? [today] : Array(candidateDays(board.value.matchDays, now: now, forward: false).suffix(1))
        }
        let boards = try await SuperLigFeed.scoreboards(days: days.isEmpty ? [today] : days, today: today)
        let matches = boards.flatMap(\.value.matches).sorted { $0.kickoff < $1.kickoff }
        return (boards.first(where: \.isStale)?.stalenessNote ?? "") + report.fixtures(matches, day: day)
    }

    /// The league's match days before or after today; a week of days when ESPN gave no calendar.
    private func candidateDays(_ matchDays: [String], now: Date, forward: Bool) -> [String] {
        let today = Self.dayKey(now)
        let known = matchDays.filter { forward ? $0 > today : $0 < today }
        guard known.isEmpty else { return known }
        return forward ? (1...7).map { Self.dayKey(now, adding: $0) } : (1...7).reversed().map { Self.dayKey(now, adding: -$0) }
    }

    private static func dayKey(_ date: Date, adding days: Int = 0) -> String {
        let calendar = Calendar.current
        let day = calendar.date(byAdding: .day, value: days, to: date) ?? date
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.calendar = calendar
        formatter.timeZone = calendar.timeZone
        formatter.dateFormat = "yyyyMMdd"
        return formatter.string(from: day)
    }
}
