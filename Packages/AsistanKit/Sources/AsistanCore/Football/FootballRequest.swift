import Foundation

public struct FootballQuery: Sendable, Equatable {
    public enum Kind: Sendable, Equatable {
        /// "Puan durumu", "Galatasaray kaçıncı".
        case standings
        /// "Fenerbahçe ne zaman oynuyor".
        case nextMatch
        /// "Galatasaray maçı kaç kaç", "Beşiktaş kazandı mı": today's match, or the last one.
        case teamMatch
        /// "Bu hafta Süper Lig maçları", "dün maç sonuçları".
        case fixtures
    }

    public enum Day: Sendable, Equatable {
        case yesterday, today, tomorrow
        /// The round being played, or the next one.
        case round
        /// The last day matches were played.
        case latest
    }

    public var team: FootballTeam?
    public var kind: Kind
    public var day: Day

    public init(team: FootballTeam?, kind: Kind, day: Day = .round) {
        self.team = team
        self.kind = kind
        self.day = day
    }
}

/// Recognises Süper Lig questions and reads what they ask.
public enum FootballRequest {
    private static let leaguePhrases = [
        "super lig", "puan durumu", "puan tablosu", "lig tablosu", "lig siralamasi", "mac sonuc", "maclarin sonuc",
        "mac var mi", "maclar", "maclari", "derbi",
    ]
    private static let teamStems = [
        "mac", "skor", "kac kac", "sonuc", "oyn", "kazan", "yendi", "yenil", "yener", "berabere", "puan", "kacinci",
        "sira", "lider", "gol", "fikstur", "rakib", "deplasman", "karsilas", "derbi", "kimle", "kiminle",
    ]
    /// News, history, tickets and other tools' work.
    private static let otherStems = [
        "haber", "hatirlat", "takvim", "not al", "mesaj", "bilet", "kuruldu", "kurulus", "mars", "forma", "baskan",
        "teknik direktor", "transfer", "cal ", "ekle", "basketbol", "voleybol",
    ]
    private static let englishLeaguePhrases = ["super lig", "turkish league", "league table", "turkish football"]
    private static let englishTeamWords: Set<String> = [
        "match", "game", "score", "scores", "play", "playing", "plays", "won", "win", "beat", "lose", "lost", "draw",
        "drew", "result", "fixture", "fixtures", "next", "standings", "table", "position", "derby",
    ]
    private static let englishOtherStems = [
        "news", "remind", "calendar", "note", "ticket", "founded", "anthem", "jersey", "president", "coach", "transfer",
        "basketball", "volleyball",
    ]

    public static func isRequest(_ text: String, language: AssistantLanguage = .turkish) -> Bool {
        let folded = " " + TurkishText.folded(text) + " "
        if language == .english {
            guard !englishOtherStems.contains(where: { folded.contains(" " + $0) }) else { return false }
            if englishLeaguePhrases.contains(where: folded.contains) { return true }
            let words = folded.split(separator: " ").map(String.init)
            return SuperLigTeams.named(in: text) != nil && words.contains(where: englishTeamWords.contains)
        }
        guard !otherStems.contains(where: { folded.contains(" " + $0) }) else { return false }
        if leaguePhrases.contains(where: { folded.contains(" " + $0) }) { return true }
        return SuperLigTeams.named(in: text) != nil && teamStems.contains { folded.contains(" " + $0) }
    }

    public static func query(_ text: String, language: AssistantLanguage = .turkish) -> FootballQuery {
        let folded = " " + TurkishText.folded(text) + " "
        let team = SuperLigTeams.named(in: text)
        let has = { (stems: [String]) in stems.contains { folded.contains(" " + $0) } }
        let english = language == .english
        let standings = english
            ? has(["table", "standings", "position", "rank", "top of", "leader", "leading"])
            : has(["puan", "tablo", "siralama", "sirada ", "kacinci", "lider", "zirve"])
        if standings { return FootballQuery(team: team, kind: .standings) }
        if let team {
            let next = english
                ? has(["when", "next", "what time", "who do", "who are", "who is"])
                : has(["ne zaman", "saat kac", "hangi gun", "sonraki", "siradaki", "gelecek mac", "oynayacak", "kimle",
                       "kiminle", "rakib"])
            return FootballQuery(team: team, kind: next ? .nextMatch : .teamMatch)
        }
        return FootballQuery(team: nil, kind: .fixtures, day: day(has, english: english))
    }

    private static func day(_ has: ([String]) -> Bool, english: Bool) -> FootballQuery.Day {
        if english {
            if has(["yesterday", "last night"]) { return .yesterday }
            if has(["today", "tonight"]) { return .today }
            if has(["tomorrow"]) { return .tomorrow }
            if has(["this week", "weekend", "round"]) { return .round }
            return has(["result"]) ? .latest : .round
        }
        if has(["dun ", "dunku"]) { return .yesterday }
        if has(["bugun", "bu aksam"]) { return .today }
        if has(["yarin"]) { return .tomorrow }
        if has(["bu hafta", "haftanin", "hafta sonu"]) { return .round }
        return has(["sonuc"]) ? .latest : .round
    }
}
