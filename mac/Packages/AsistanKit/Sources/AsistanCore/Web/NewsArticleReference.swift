import Foundation

/// Which of the headlines just read a request points at: "üçüncü haberi aç", "Claude'un keşfettiği buluşu açar
/// mısın", "tell me more about the second one". Recognizers misspell names ("Cloud'un" for "Claude'un"), so words
/// match loosely; a request has to point at a headline clearly, or "Telegram'ı aç" after a headline about Telegram
/// would read the news instead of opening the app.
public enum NewsArticleReference {
    public struct Request: Equatable, Sendable {
        public let item: RSSHeadlines.Item
        /// "Aç", "open": also shown in the browser, not only told.
        public let inBrowser: Bool

        public init(item: RSSHeadlines.Item, inBrowser: Bool) {
            self.item = item
            self.inBrowser = inBrowser
        }
    }

    public static func find(_ command: String, lastReading: [RSSHeadlines.Item],
                            all: [RSSHeadlines.Item]) -> Request? {
        let words = words(command)
        guard asksForArticle(words), !all.isEmpty else { return nil }
        let place = words.lazy.compactMap(ordinal).first
        // "Haberleri oku", "son başlıkları anlat" ask for the headlines themselves.
        if place == nil, words.contains(where: { word in listWords.contains { word.hasPrefix($0) } }) { return nil }
        let opens = words.contains(where: isOpenWord) || words.contains { browserWords.contains($0) }
        let namesNews = words.contains { word in newsWords.contains { word.hasPrefix($0) } }
        let named = words.filter { ordinal($0) == nil && !NewsRequest.isTopicWord($0) && isNamed($0) }
        // "İkincisini aç", "the second one"; not "ikinci sekmeyi aç" or "open the last tab".
        if let place, namesNews || named.isEmpty {
            let item = place == .last ? lastReading.last : lastReading[safe: place.index]
            return item.map { Request(item: $0, inBrowser: opens) }
        }
        let content = named.filter { $0.count >= 4 }
        let scored = all.map { item in (item, score(content, against: Self.words(item.title))) }
        // A bare "aç" with names is how apps are opened too ("Claude Code'u aç"), so it needs more to go on.
        let tells = words.contains { word in cueWords.contains { word.hasPrefix($0) } }
        let needed = namesNews ? 1 : tells ? 2 : 3
        guard let best = scored.max(by: { $0.1 < $1.1 }), best.1 >= needed else { return nil }
        return Request(item: best.0, inBrowser: opens)
    }

    /// "aç", "anlat", "oku", "detay", "open", "tell me more".
    static func asksForArticle(_ words: [String]) -> Bool {
        words.contains { word in isOpenWord(word) || cueWords.contains { word.hasPrefix($0) } }
    }

    private enum Place: Equatable {
        case number(Int)
        case last

        var index: Int {
            if case let .number(number) = self { return number - 1 }
            return -1
        }
    }

    /// Turkish ones take endings ("üçüncüsünü"); "ilk" only short ones, not "ilkbahar".
    private static let ordinals: [(prefix: String, place: Place)] = [
        ("ilk", .number(1)), ("birinci", .number(1)), ("ikinci", .number(2)), ("ucuncu", .number(3)),
        ("dorduncu", .number(4)), ("besinci", .number(5)), ("sonuncu", .last),
    ]
    private static let englishOrdinals: [String: Place] = [
        "first": .number(1), "second": .number(2), "third": .number(3), "fourth": .number(4), "fifth": .number(5),
        "last": .last,
    ]
    private static let openWords = ["ac", "acar", "acin", "acip", "acsan", "acabil", "aciver", "acmak", "open"]
    private static let browserWords: Set<String> = [
        "tarayici", "tarayicida", "safari", "safaride", "chrome", "firefox", "firefoxta", "browser",
    ]
    private static let cueWords = ["anlat", "detay", "ayrinti", "oku", "ozetle", "icerig", "hakkinda", "read",
                                   "tell", "detail", "summar", "more"]
    private static let newsWords = ["haber", "basli", "makale", "news", "headline", "story", "article"]
    private static let listWords = ["haberler", "basliklar", "headlines"]
    /// Said around a request without telling which headline it means.
    private static let fillers: Set<String> = [
        "misin", "musun", "misiniz", "bana", "biraz", "daha", "bilgi", "simdi", "lutfen", "sunu", "bunu", "onu",
        "olan", "hangi", "icin", "gibi", "kadar", "neler", "nedir", "ne", "mi", "mu", "da", "de", "bu", "su", "o",
        "about", "please", "that", "this", "with", "from", "what", "says", "the", "one", "it", "me", "a", "an", "of",
        "to",
    ]

    private static func isOpenWord(_ word: String) -> Bool {
        word == "ac" || openWords.dropFirst().contains { word.hasPrefix($0) }
    }

    /// A word that says what the request is about, rather than how it is asked.
    private static func isNamed(_ word: String) -> Bool {
        !fillers.contains(word) && !isOpenWord(word) && !browserWords.contains(word)
            && !cueWords.contains { word.hasPrefix($0) } && !newsWords.contains { word.hasPrefix($0) }
    }

    private static func ordinal(_ word: String) -> Place? {
        englishOrdinals[word] ?? ordinals.first { ordinal in
            word.hasPrefix(ordinal.prefix) && (ordinal.prefix.count >= 5 || word.count <= ordinal.prefix.count + 3)
        }?.place
    }

    private static func score(_ said: [String], against title: [String]) -> Int {
        said.filter { word in title.contains { matches(word, $0) } }.count
    }

    /// The same word with another ending ("buluşu", "buluş"), or one a recognizer misheard ("cloudun", "claudeun").
    static func matches(_ said: String, _ title: String) -> Bool {
        guard said.count >= 4, title.count >= 4 else { return false }
        let common = zip(said, title).prefix { $0 == $1 }.count
        if common >= min(5, said.count, title.count) { return true }
        return said.count >= 5 && title.count >= 5 && said.prefix(2) == title.prefix(2)
            && FuzzyText.levenshtein(Array(said), Array(title)) <= 2
    }

    private static func words(_ text: String) -> [String] {
        TurkishText.folded(text).split(separator: " ").map(String.init)
    }
}

private extension Array {
    subscript(safe index: Int) -> Element? {
        indices.contains(index) ? self[index] : nil
    }
}
