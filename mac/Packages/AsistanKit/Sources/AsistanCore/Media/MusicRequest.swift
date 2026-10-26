import Foundation

/// Music asked for on a named service: "YouTube'da Tarkan aç", "YouTube Music'te Sezen Aksu çal", "Kuzu Kuzu'yu
/// Spotify'dan çal", "play Tarkan on Deezer". A service said as the object ("YouTube'u aç") or with nothing to play
/// is not one: that opens the app or the site.
public struct MusicRequest: Sendable, Equatable {
    public let query: String
    public let service: MusicService

    public init(query: String, service: MusicService) {
        self.query = query
        self.service = service
    }

    private struct Word {
        let said: String
        let folded: String
    }

    /// Folded words of each name; the last may carry a case ending ("youtubeda", "musicten"). Longer names first.
    private static let spokenNames: [(MusicService, [String])] = [
        (.youTubeMusic, ["youtube", "music"]), (.youTubeMusic, ["youtube", "muzik"]),
        (.appleMusic, ["apple", "music"]), (.appleMusic, ["apple", "muzik"]),
        (.youTube, ["youtube"]), (.youTube, ["yutub"]), (.youTube, ["yutup"]),
        (.spotify, ["spotify"]), (.deezer, ["deezer"]),
    ]
    /// "-de" and "-den" in every harmony; "-yu", "-ı" (the service as the object) are not here.
    private static let placeEndings: Set<String> = ["", "da", "de", "ta", "te", "dan", "den", "tan", "ten"]
    /// Said apart from the name: "YouTube da", "Spotify üzerinden".
    private static let placeWords: Set<String> = [
        "da", "de", "ta", "te", "dan", "den", "tan", "ten", "uzerinden", "ustunden", "ile",
    ]
    private static let englishPlaces: Set<String> = ["on", "in", "from", "via", "using", "with"]
    private static let turkishVerbs: Set<String> = [
        "ac", "cal", "oynat", "baslat", "dinlet", "dinle", "izle", "izlet", "koy", "acar", "calar", "oynatir", "koyar",
        "acsana", "calsana", "oynatsana", "koysana", "acabilir", "calabilir", "oynatabilir", "acin", "calin",
    ]
    private static let englishVerbs: [[String]] = [["put", "on"], ["listen", "to"], ["play"], ["start"], ["watch"], ["open"]]
    private static let leading: Set<String> = ["bilge", "hadi", "lutfen", "bana", "hey", "please", "can", "could", "you"]
    private static let trailing: Set<String> = [
        "misin", "musun", "misiniz", "musunuz", "lutfen", "bakalim", "please", "now", "for", "me",
    ]
    /// Around the name they say "music" rather than which: "Tarkan şarkıları" is Tarkan. English words are whole, so
    /// "Songül" stays a name.
    private static let musicStems = ["sarki", "muzik", "muzig", "parca", "album"]
    private static let englishMusicWords: Set<String> = ["song", "songs", "music", "track", "tracks"]
    private static let articles: Set<String> = ["bir", "biraz", "birkac", "some", "a", "by"]
    /// A request made only of such words names nothing to search for ("Spotify'da müzik çal", "YouTube'da bir video aç").
    private static let vagueWords: Set<String> = ["something", "anything", "su", "bu", "this", "that"]

    public static func parse(_ text: String) -> MusicRequest? {
        let words = joiningYouTube(text.split(whereSeparator: \.isWhitespace).compactMap { raw -> Word? in
            let said = String(raw).trimmingCharacters(in: .punctuationCharacters.subtracting(["'", "’"]))
            let folded = TurkishText.folded(said).replacingOccurrences(of: " ", with: "")
            return folded.isEmpty ? nil : Word(said: said, folded: folded)
        })
        guard let (service, nameStart, nameEnd) = serviceName(in: words.map(\.folded)) else { return nil }
        let start = nameStart > 0 && englishPlaces.contains(words[nameStart - 1].folded) ? nameStart - 1 : nameStart
        var rest = trimmed(Array(words[..<start] + words[nameEnd...]))
        if let last = rest.last, turkishVerbs.contains(last.folded) {
            rest.removeLast()
        } else if let opener = englishVerbs.first(where: { rest.map(\.folded).starts(with: $0) }) {
            rest.removeFirst(opener.count)
        } else {
            return nil
        }
        let query = query(from: rest)
        return query.isEmpty ? nil : MusicRequest(query: query, service: service)
    }

    /// The service and where its name (with a separate "da", "üzerinden") is; nil when the first name found is not
    /// said as a place.
    private static func serviceName(in words: [String]) -> (MusicService, Int, Int)? {
        for index in words.indices {
            for (service, stems) in spokenNames {
                let last = index + stems.count - 1
                guard last < words.count, Array(words[index..<last]) == Array(stems.dropLast()), let stem = stems.last,
                      words[last].hasPrefix(stem) else { continue }
                let ending = String(words[last].dropFirst(stem.count))
                guard placeEndings.contains(ending) else { return nil }
                var end = last + 1
                if ending.isEmpty, end < words.count, placeWords.contains(words[end]) { end += 1 }
                return (service, index, end)
            }
        }
        return nil
    }

    /// "You Tube'da" as a recognizer may write it.
    private static func joiningYouTube(_ words: [Word]) -> [Word] {
        var joined: [Word] = []
        for word in words {
            if let previous = joined.last, previous.folded == "you", word.folded.hasPrefix("tube") {
                joined[joined.count - 1] = Word(said: previous.said + word.said, folded: previous.folded + word.folded)
            } else {
                joined.append(word)
            }
        }
        return joined
    }

    private static func trimmed(_ words: [Word]) -> [Word] {
        var slice = words[...]
        while let first = slice.first, leading.contains(first.folded) { slice.removeFirst() }
        while let last = slice.last, trailing.contains(last.folded) { slice.removeLast() }
        return Array(slice)
    }

    /// The words as said, each cut at its case ending ("Kuzu Kuzu'yu" → "Kuzu Kuzu", "Tarkan'ın şarkılarını" →
    /// "Tarkan"), without "bir", "şarkı", "müzik" around them.
    private static func query(from words: [Word]) -> String {
        let cut = words.compactMap { word -> Word? in
            guard let stem = word.said.split(whereSeparator: { $0 == "'" || $0 == "’" }).first else { return nil }
            return Word(said: String(stem), folded: TurkishText.folded(String(stem)))
        }
        let isMusicWord = { (word: Word) in
            musicStems.contains(where: word.folded.hasPrefix) || englishMusicWords.contains(word.folded)
        }
        let isVague = { (word: Word) in
            isMusicWord(word) || word.folded.hasPrefix("video") || vagueWords.contains(word.folded) || articles.contains(word.folded)
        }
        guard !cut.allSatisfy(isVague) else { return "" }
        var slice = cut[...]
        while let first = slice.first, isMusicWord(first) || articles.contains(first.folded) { slice.removeFirst() }
        while let last = slice.last, isMusicWord(last) { slice.removeLast() }
        return slice.map(\.said).joined(separator: " ")
    }
}
