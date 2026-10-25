import Foundation

/// Süper Lig answers as spoken sentences. Scores are said as "Galatasaray 2, Fenerbahçe 1".
public struct FootballReport: Sendable {
    private static let listedTeams = 5
    private static let turkishOrdinals = [
        "birinci", "ikinci", "üçüncü", "dördüncü", "beşinci", "altıncı", "yedinci", "sekizinci", "dokuzuncu", "onuncu",
    ]
    private static let englishOrdinals = [
        "first", "second", "third", "fourth", "fifth", "sixth", "seventh", "eighth", "ninth", "tenth", "eleventh",
        "twelfth", "thirteenth", "fourteenth", "fifteenth", "sixteenth", "seventeenth", "eighteenth", "nineteenth",
        "twentieth",
    ]

    public let now: Date
    public let calendar: Calendar
    public let language: AssistantLanguage

    public init(now: Date, calendar: Calendar = .current, language: AssistantLanguage) {
        self.now = now
        self.calendar = calendar
        self.language = language
    }

    private var english: Bool { language == .english }

    // MARK: - One match

    public func match(_ match: SoccerMatch) -> String {
        let (home, away) = names(match)
        let score = scoreLine(match)
        switch (language, match.state) {
        case (.english, .scheduled): return "\(home) v \(away) is \(dayPhrase(match.kickoff)) at \(time(match.kickoff))."
        case (.english, .live): return "\(home) v \(away) is under way, minute \(minute(match)): \(score)."
        case (.english, .halftime): return "It's half-time in \(home) v \(away): \(score)."
        case (.english, .finished): return "Full time \(dayPhrase(match.kickoff)): \(score)."
        case (.english, .postponed): return "\(home) v \(away) has been postponed."
        case (.turkish, .scheduled): return "\(home) \(away) maçı \(dayPhrase(match.kickoff)) \(time(match.kickoff))."
        case (.turkish, .live): return "\(home) \(away) maçı oynanıyor, dakika \(minute(match)): \(score)."
        case (.turkish, .halftime): return "\(home) \(away) maçında devre arası: \(score)."
        case (.turkish, .finished): return "\(capitalized(dayPhrase(match.kickoff))) oynanan maçta \(score)."
        case (.turkish, .postponed): return "\(home) \(away) maçı ertelendi."
        }
    }

    public func noMatch(for team: FootballTeam, upcoming: Bool) -> String {
        switch (language, upcoming) {
        case (.english, true): "I couldn't find an upcoming Süper Lig match for \(team.name)."
        case (.english, false): "I couldn't find a recent Süper Lig match for \(team.name)."
        case (.turkish, true): "\(team.name) için yaklaşan bir Süper Lig maçı bulamadım."
        case (.turkish, false): "\(team.name) için yakın zamanda oynanmış bir Süper Lig maçı bulamadım."
        }
    }

    // MARK: - A day or a round

    public func fixtures(_ matches: [SoccerMatch], day: FootballQuery.Day) -> String {
        guard !matches.isEmpty else { return nothingOn(day) }
        let byDay = Dictionary(grouping: matches) { calendar.startOfDay(for: $0.kickoff) }
        let showsDays = byDay.count > 1 || day == .round || day == .latest
        let parts = byDay.keys.sorted().map { date in
            let items = (byDay[date] ?? []).sorted { $0.kickoff < $1.kickoff }.map(item).joined(separator: "; ")
            return showsDays ? "\(capitalized(weekday(date))): \(items)." : "\(items)."
        }
        return ([heading(day)] + parts).joined(separator: " ")
    }

    private func item(_ match: SoccerMatch) -> String {
        let (home, away) = names(match)
        switch (language, match.state) {
        case (.english, .scheduled): return "\(home) v \(away) at \(time(match.kickoff))"
        case (.turkish, .scheduled): return "\(time(match.kickoff)) \(home) \(away)"
        case (.english, .live): return "\(scoreLine(match)), minute \(minute(match))"
        case (.turkish, .live): return "\(scoreLine(match)), dakika \(minute(match))"
        case (.english, .halftime): return "\(scoreLine(match)), half-time"
        case (.turkish, .halftime): return "\(scoreLine(match)), devre arası"
        case (_, .finished): return scoreLine(match)
        case (.english, .postponed): return "\(home) v \(away) postponed"
        case (.turkish, .postponed): return "\(home) \(away) ertelendi"
        }
    }

    private func heading(_ day: FootballQuery.Day) -> String {
        switch (language, day) {
        case (.english, .yesterday): "Yesterday's Süper Lig matches:"
        case (.english, .today): "Today's Süper Lig matches:"
        case (.english, .tomorrow): "Tomorrow's Süper Lig matches:"
        case (.english, .round): "This round of the Süper Lig:"
        case (.english, .latest): "The latest Süper Lig results:"
        case (.turkish, .yesterday): "Dünkü Süper Lig maçları:"
        case (.turkish, .today): "Bugünkü Süper Lig maçları:"
        case (.turkish, .tomorrow): "Yarınki Süper Lig maçları:"
        case (.turkish, .round): "Bu haftanın Süper Lig maçları:"
        case (.turkish, .latest): "Son oynanan Süper Lig maçları:"
        }
    }

    private func nothingOn(_ day: FootballQuery.Day) -> String {
        switch (language, day) {
        case (.english, .yesterday): "There were no Süper Lig matches yesterday."
        case (.english, .today): "There are no Süper Lig matches today."
        case (.english, .tomorrow): "There are no Süper Lig matches tomorrow."
        case (.english, _): "I couldn't find any Süper Lig matches."
        case (.turkish, .yesterday): "Dün Süper Lig maçı yoktu."
        case (.turkish, .today): "Bugün Süper Lig maçı yok."
        case (.turkish, .tomorrow): "Yarın Süper Lig maçı yok."
        case (.turkish, _): "Süper Lig maçı bulamadım."
        }
    }

    // MARK: - Standings

    public func standings(_ rows: [StandingRow], team: FootballTeam?) -> String {
        guard let leader = rows.first else {
            return english ? "The Süper Lig table isn't available." : "Süper Lig puan durumu şu an yok."
        }
        if let team, let row = rows.first(where: { SuperLigTeams.team(espnName: $0.espnName) == team }) {
            return teamStanding(row, team: team, leader: leader)
        }
        let top = rows.prefix(Self.listedTeams).enumerated().map { index, row in
            let name = SuperLigTeams.spokenName(espnName: row.espnName)
            if english { return index == 0 ? "\(name) top with \(row.points) points" : "\(name) \(ordinal(row.rank)) with \(row.points)" }
            return index == 0 ? "lider \(name) \(row.points) puan" : "\(ordinal(row.rank)) \(name) \(row.points)"
        }
        let opening = english ? "Süper Lig table: " : "Süper Lig puan durumu: "
        return opening + top.joined(separator: ", ") + "."
    }

    private func teamStanding(_ row: StandingRow, team: FootballTeam, leader: StandingRow) -> String {
        let leaderName = SuperLigTeams.spokenName(espnName: leader.espnName)
        let isLeader = row.espnName == leader.espnName
        if english {
            let sentence = "\(team.name) are \(isLeader ? "top of the table" : ordinal(row.rank)) with \(row.points) points from \(row.played) games."
            return isLeader ? sentence : sentence + " \(leaderName) lead with \(leader.points)."
        }
        let place = isLeader ? "lider" : "\(ordinal(row.rank)) sırada"
        let sentence = "\(team.name) \(row.played) maçta \(row.points) puanla \(place)."
        return isLeader ? sentence : sentence + " Lider \(leaderName), \(leader.points) puan."
    }

    func ordinal(_ rank: Int) -> String {
        if english { return Self.englishOrdinals.indices.contains(rank - 1) ? Self.englishOrdinals[rank - 1] : "number \(rank)" }
        switch rank {
        case 1...10: return Self.turkishOrdinals[rank - 1]
        case 11...19: return "on " + Self.turkishOrdinals[rank - 11]
        case 20: return "yirminci"
        default: return "\(rank). "
        }
    }

    // MARK: - Pieces

    private func names(_ match: SoccerMatch) -> (String, String) {
        (SuperLigTeams.spokenName(espnName: match.home.espnName), SuperLigTeams.spokenName(espnName: match.away.espnName))
    }

    private func scoreLine(_ match: SoccerMatch) -> String {
        let (home, away) = names(match)
        return "\(home) \(match.home.score ?? 0), \(away) \(match.away.score ?? 0)"
    }

    /// "67'" → "67"; "90'+3'" → "90 artı 3".
    func minute(_ match: SoccerMatch) -> String {
        let clock = (match.clock ?? "").replacingOccurrences(of: "'", with: "")
        let parts = clock.split(separator: "+").map { $0.trimmingCharacters(in: .whitespaces) }
        guard let base = parts.first, !base.isEmpty else { return "?" }
        guard parts.count > 1 else { return base }
        return base + (english ? " plus " : " artı ") + parts[1]
    }

    /// "bugün", "yarın", "dün", a weekday within the week, or a date further away.
    func dayPhrase(_ date: Date) -> String {
        let days = calendar.dateComponents([.day], from: calendar.startOfDay(for: now), to: calendar.startOfDay(for: date)).day ?? 0
        switch (language, days) {
        case (.english, 0): return "today"
        case (.english, 1): return "tomorrow"
        case (.english, -1): return "yesterday"
        case (.english, -6...6): return "on \(weekday(date))"
        case (.english, _): return "on " + date.formatted(format.weekday(.wide).month(.wide).day())
        case (.turkish, 0): return "bugün"
        case (.turkish, 1): return "yarın"
        case (.turkish, -1): return "dün"
        case (.turkish, -6...6): return weekday(date)
        case (.turkish, _): return date.formatted(format.day().month(.wide).weekday(.wide))
        }
    }

    private func weekday(_ date: Date) -> String {
        date.formatted(format.weekday(.wide))
    }

    /// "21:30'da" in Turkish (with the ending the dative needs), "9:30 PM" in English.
    func time(_ date: Date) -> String {
        if english { return date.formatted(format.hour().minute()) }
        let parts = calendar.dateComponents([.hour, .minute], from: date)
        return TurkishGrammar.timeLocative(hour: parts.hour ?? 0, minute: parts.minute ?? 0)
    }

    private var format: Date.FormatStyle {
        Date.FormatStyle(date: .omitted, time: .omitted, locale: language.locale, calendar: calendar, timeZone: calendar.timeZone)
    }

    private func capitalized(_ text: String) -> String {
        text.prefix(1).uppercased(with: language.locale) + text.dropFirst()
    }
}
