import Foundation

public struct FootballTeam: Sendable, Equatable {
    /// Spelled the Turkish way, which English speakers use too ("Fenerbahçe").
    public let name: String
    /// Folded names ESPN gives the club ("fenerbahce", "istanbul basaksehir").
    let espnNames: [String]
    /// Folded names and nicknames people say.
    let aliases: [String]

    init(_ name: String, espn: [String], aliases: [String] = []) {
        self.name = name
        espnNames = espn
        self.aliases = aliases
    }
}

/// Süper Lig clubs (and recent ones) with the names people use for them.
public enum SuperLigTeams {
    /// Endings a short name like "GS" takes: "GS'nin", "FB'ye".
    private static let shortEndings: Set<String> = ["", "nin", "in", "un", "nun", "ye", "yi", "a", "e", "ya", "ile", "li", "lu"]
    /// More letters than this after a name is another word ("fenerbahce" is not "fener" + an ending).
    private static let longestEnding = 4

    public static let all: [FootballTeam] = [
        FootballTeam("Galatasaray", espn: ["galatasaray"], aliases: ["galatasaray", "gs", "cimbom", "cim bom"]),
        FootballTeam("Fenerbahçe", espn: ["fenerbahce"], aliases: ["fenerbahce", "fener", "fb", "fener bahce"]),
        FootballTeam("Beşiktaş", espn: ["besiktas"], aliases: ["besiktas", "bjk"]),
        FootballTeam("Trabzonspor", espn: ["trabzonspor"], aliases: ["trabzonspor", "trabzon", "ts"]),
        FootballTeam("Başakşehir", espn: ["istanbul basaksehir", "basaksehir"], aliases: ["basaksehir", "ibfk"]),
        FootballTeam("Çaykur Rizespor", espn: ["caykur rizespor", "rizespor"], aliases: ["rizespor", "caykur rizespor", "rize"]),
        FootballTeam("Göztepe", espn: ["goztepe"], aliases: ["goztepe"]),
        FootballTeam("Kasımpaşa", espn: ["kasimpasa"], aliases: ["kasimpasa"]),
        FootballTeam("Konyaspor", espn: ["konyaspor"], aliases: ["konyaspor", "konya"]),
        FootballTeam("Samsunspor", espn: ["samsunspor"], aliases: ["samsunspor", "samsun"]),
        FootballTeam("Gaziantep FK", espn: ["gaziantep fk", "gaziantep"], aliases: ["gaziantep", "antep"]),
        FootballTeam("Gençlerbirliği", espn: ["genclerbirligi"], aliases: ["genclerbirligi", "gencler"]),
        FootballTeam("Eyüpspor", espn: ["eyupspor"], aliases: ["eyupspor", "eyup"]),
        FootballTeam("Alanyaspor", espn: ["alanyaspor"], aliases: ["alanyaspor", "alanya"]),
        FootballTeam("Kocaelispor", espn: ["kocaelispor"], aliases: ["kocaelispor", "kocaeli"]),
        FootballTeam("Erzurumspor", espn: ["erzurum bb", "erzurumspor", "erzurumspor fk"], aliases: ["erzurumspor", "erzurum"]),
        FootballTeam("Çorum FK", espn: ["corum fk"], aliases: ["corum"]),
        FootballTeam("Amedspor", espn: ["amed sfk", "amedspor"], aliases: ["amedspor", "amed"]),
        FootballTeam("Antalyaspor", espn: ["antalyaspor"], aliases: ["antalyaspor", "antalya"]),
        FootballTeam("Sivasspor", espn: ["sivasspor"], aliases: ["sivasspor", "sivas"]),
        FootballTeam("Kayserispor", espn: ["kayserispor"], aliases: ["kayserispor", "kayseri"]),
        FootballTeam("Hatayspor", espn: ["hatayspor"], aliases: ["hatayspor", "hatay"]),
        FootballTeam("Adana Demirspor", espn: ["adana demirspor"], aliases: ["adana demirspor", "adana demir", "demirspor"]),
        FootballTeam("Bodrum FK", espn: ["bodrum fk", "bodrumspor"], aliases: ["bodrumspor", "bodrum"]),
        FootballTeam("Fatih Karagümrük", espn: ["fatih karagumruk", "karagumruk"], aliases: ["karagumruk"]),
        FootballTeam("Pendikspor", espn: ["pendikspor"], aliases: ["pendikspor", "pendik"]),
        FootballTeam("Ankaragücü", espn: ["mke ankaragucu", "ankaragucu"], aliases: ["ankaragucu"]),
        FootballTeam("İstanbulspor", espn: ["istanbulspor"], aliases: ["istanbulspor"]),
    ]

    /// The club named in a request; the longest matching name wins ("Adana Demirspor" over "Adana").
    public static func named(in text: String) -> FootballTeam? {
        let folded = TurkishText.folded(text)
        let words = folded.split(separator: " ").map(String.init)
        var best: (team: FootballTeam, length: Int)?
        for team in all {
            for alias in team.aliases where alias.count > (best?.length ?? 0) && matches(alias, words: words, folded: folded) {
                best = (team, alias.count)
            }
        }
        return best?.team
    }

    /// The club ESPN calls `espnName`, if it is one of these.
    public static func team(espnName: String) -> FootballTeam? {
        let folded = TurkishText.folded(espnName)
        return all.first { $0.espnNames.contains(folded) }
    }

    /// The Turkish spelling when the club is known, ESPN's otherwise.
    public static func spokenName(espnName: String) -> String {
        team(espnName: espnName)?.name ?? espnName
    }

    private static func matches(_ alias: String, words: [String], folded: String) -> Bool {
        if alias.contains(" ") { return (" " + folded + " ").contains(" " + alias) }
        return words.contains { word in
            guard word.hasPrefix(alias) else { return false }
            let ending = String(word.dropFirst(alias.count))
            return alias.count <= 3 ? shortEndings.contains(ending) : ending.count <= longestEnding
        }
    }
}
