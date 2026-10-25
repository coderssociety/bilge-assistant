import Foundation

public enum PodcastCommand: Sendable, Equatable {
    case playLatest(show: String)
    case checkNew(show: String)
}

/// "Mesele Ekonomi podcastinin son bölümünü aç", "Medyascope'un yeni bölümü var mı"; "play the latest episode of
/// The Daily", "does Lex Fridman have a new episode". Pausing and seeking an episode are media commands.
public enum PodcastRequest {
    private static let playVerbs: Set<String> = [
        "ac", "acar", "acsana", "acabilir", "acin", "cal", "calar", "calsana", "calabilir", "baslat", "baslatir", "dinlet",
        "dinle", "koy", "oynat",
    ]
    private static let askWords: Set<String> = [
        "var", "cikti", "cikmis", "geldi", "gelmis", "yayinlandi", "yayinlanmis", "zaman", "mi", "mu",
    ]
    private static let politeness: Set<String> = ["misin", "musun", "misiniz", "musunuz", "lutfen", "acaba"]
    private static let leadingFillers: Set<String> = ["bana", "lutfen", "hadi", "simdi", "acaba"]
    /// A TV series, a video or a book has episodes and chapters too.
    private static let otherKinds = ["dizi", "video", "youtube", "kitab", "kitap", "film", "sezon"]

    public static func parse(_ text: String, language: AssistantLanguage = .turkish) -> PodcastCommand? {
        let tokens = SpokenToken.split(text)
        guard !tokens.isEmpty else { return nil }
        return language == .english ? english(tokens) : turkish(tokens)
    }

    // MARK: - Turkish

    private static func turkish(_ all: [SpokenToken]) -> PodcastCommand? {
        var tokens = all
        while let last = tokens.last, tokens.count > 1, politeness.contains(last.folded) { tokens.removeLast() }
        let words = tokens.map(\.folded)
        guard !words.contains(where: { word in otherKinds.contains(where: word.hasPrefix) }) else { return nil }
        let showEnd: Int
        let rest: ArraySlice<String>
        let saysPodcast: Bool
        if let podcast = words.firstIndex(where: { $0.hasPrefix("podcast") }) {
            (showEnd, rest, saysPodcast) = (podcast, words[(podcast + 1)...], true)
        } else if let episode = words.indices.dropFirst().first(where: { words[$0].hasPrefix("bolum") }),
                  ["son", "yeni"].contains(words[episode - 1]) {
            (showEnd, rest, saysPodcast) = (episode - 1, words[(episode - 1)...], false)
        } else {
            return nil
        }
        guard let show = showName(tokens[..<showEnd]), let last = rest.last else { return nil }
        let asks = rest.contains(where: askWords.contains)
        if asks, rest.contains("yeni") || rest.contains("zaman") { return .checkNew(show: show) }
        if playVerbs.contains(last) { return .playLatest(show: show) }
        if saysPodcast, asks, rest.contains(where: { $0.hasPrefix("bolum") }) { return .checkNew(show: show) }
        return nil
    }

    private static func showName(_ tokens: ArraySlice<SpokenToken>) -> String? {
        var words = Array(tokens)
        while let first = words.first, leadingFillers.contains(first.folded) { words.removeFirst() }
        if words.last?.folded == "en" { words.removeLast() }
        let name = words.map(\.stem).joined(separator: " ")
        return name.isEmpty ? nil : name
    }

    // MARK: - English

    private static let englishPlayLeads: [[String]] = [["play"], ["put", "on"], ["start"], ["listen", "to"], ["open"]]
    private static let englishFillers: Set<String> = ["the", "a", "an", "latest", "newest", "last", "new", "most", "recent"]
    private static let englishReleaseVerbs: Set<String> = [
        "have", "has", "released", "release", "put", "publish", "published", "got", "drop", "dropped", "post", "posted",
    ]

    private static func english(_ tokens: [SpokenToken]) -> PodcastCommand? {
        let words = tokens.map(\.folded)
        let lead = englishPlayLeads.first { words.starts(with: $0) }
        if let episode = words.firstIndex(where: { $0 == "episode" || $0 == "episodes" }) {
            let show: String?
            if let of = words[episode...].firstIndex(of: "of") {
                show = englishShow(tokens[(of + 1)...], droppingLeadingFillers: false)
            } else if let subject = words.firstIndex(where: { ["does", "did", "has"].contains($0) }), subject + 1 < episode,
                      let verb = words[(subject + 1)..<episode].firstIndex(where: englishReleaseVerbs.contains), verb > subject + 1 {
                show = englishShow(tokens[(subject + 1)..<verb], droppingLeadingFillers: false)
            } else {
                show = nil
            }
            return show.map { lead == nil ? .checkNew(show: $0) : .playLatest(show: $0) }
        }
        guard let lead, let podcast = words.lastIndex(of: "podcast"), podcast > lead.count,
              let show = englishShow(tokens[lead.count..<podcast], droppingLeadingFillers: true) else { return nil }
        return .playLatest(show: show)
    }

    private static func englishShow(_ tokens: ArraySlice<SpokenToken>, droppingLeadingFillers: Bool) -> String? {
        var words = Array(tokens)
        while droppingLeadingFillers, let first = words.first, englishFillers.contains(first.folded) { words.removeFirst() }
        while let last = words.last, ["podcast", "please"].contains(last.folded) { words.removeLast() }
        let name = words.map(\.stem).joined(separator: " ")
        return name.isEmpty ? nil : name
    }
}
