import Foundation

/// Where the headlines come from. Each language has a few, read in turn when the user asks for another source
/// ("başka bir kaynak"), or by name ("TRT haberleri").
public enum NewsSource: String, Sendable, CaseIterable {
    case anadolu, trtHaber, bbcTurkish, bbcNews, guardian, npr

    public static func sources(for language: AssistantLanguage) -> [NewsSource] {
        switch language {
        case .turkish: [.anadolu, .trtHaber, .bbcTurkish]
        case .english: [.bbcNews, .guardian, .npr]
        }
    }

    public static func preferred(for language: AssistantLanguage) -> NewsSource {
        sources(for: language)[0]
    }

    public var language: AssistantLanguage {
        Self.sources(for: .turkish).contains(self) ? .turkish : .english
    }

    /// "Anadolu Ajansı'ndan", "from BBC News": the source in a sentence about where the headlines come from.
    public var from: String {
        switch self {
        case .anadolu: "Anadolu Ajansı'ndan"
        case .trtHaber: "TRT Haber'den"
        case .bbcTurkish: "BBC Türkçe'den"
        case .bbcNews: "from BBC News"
        case .guardian: "from The Guardian"
        case .npr: "from NPR"
        }
    }

    /// The feed for `topic`; nil where the source has no feed of its own for it (BBC Türkçe has one feed).
    public func feed(_ topic: NewsRequest.Topic) -> URL? {
        let address: String? = switch self {
        case .anadolu:
            "https://www.aa.com.tr/tr/rss/default?cat=" + Self.slug(topic, ["guncel", "ekonomi", "spor", "dunya", "bilim-teknoloji"])
        case .trtHaber:
            "https://www.trthaber.com/\(Self.slug(topic, ["manset", "ekonomi", "spor", "dunya", "bilim_teknoloji"]))_articles.rss"
        case .bbcTurkish:
            topic == .general ? "https://feeds.bbci.co.uk/turkce/rss.xml" : nil
        case .bbcNews:
            "https://feeds.bbci.co.uk/" + Self.slug(topic, ["news/rss.xml", "news/business/rss.xml", "sport/rss.xml",
                                                          "news/world/rss.xml", "news/technology/rss.xml"])
        case .guardian:
            "https://www.theguardian.com/\(Self.slug(topic, ["international", "business", "sport", "world", "technology"]))/rss"
        case .npr:
            "https://feeds.npr.org/\(Self.slug(topic, ["1001", "1006", "1055", "1004", "1019"]))/rss.xml"
        }
        return address.flatMap(URL.init(string:))
    }

    /// The source after this one, in its language, that has a feed for `topic`.
    public func next(for topic: NewsRequest.Topic) -> NewsSource {
        let all = Self.sources(for: language)
        let start = all.firstIndex(of: self) ?? 0
        return (1..<all.count).lazy.map { all[(start + $0) % all.count] }.first { $0.feed(topic) != nil } ?? self
    }

    private static func source(named word: String, language: AssistantLanguage) -> NewsSource? {
        if word.hasPrefix("anadolu") { return .anadolu }
        if word.hasPrefix("trt") { return .trtHaber }
        if word.hasPrefix("bbc") { return language == .turkish ? .bbcTurkish : .bbcNews }
        if word.hasPrefix("guardian") { return .guardian }
        return word.hasPrefix("npr") ? .npr : nil
    }

    /// The source a command names: "TRT'den haberler", "BBC haberleri", "Anadolu Ajansı".
    public static func named(in command: String, language: AssistantLanguage) -> NewsSource? {
        for word in words(command) {
            // "AA'dan": the apostrophe is dropped, so "aa" with a short ending.
            if word.hasPrefix("aa"), word.count <= 5, word.dropFirst(2).first != "a" { return .anadolu }
            if let source = source(named: word, language: language) { return source }
        }
        return nil
    }

    private static let otherWords = ["baska", "farkli", "diger", "another", "other", "different", "else"]
    private static let sourceWords = ["kaynak", "site", "yerden", "ajans", "kanal", "gazete", "source", "outlet",
                                      "paper", "somewhere"]

    /// "Başka bir kaynak", "farklı bir siteden", "another source", "somewhere else".
    public static func asksForAnother(_ command: String) -> Bool {
        let words = words(command)
        return words.contains { word in otherWords.contains { word.hasPrefix($0) } }
            && words.contains { word in sourceWords.contains { word.hasPrefix($0) } }
    }

    private static func slug(_ topic: NewsRequest.Topic, _ slugs: [String]) -> String {
        slugs[NewsRequest.Topic.allCases.firstIndex(of: topic) ?? 0]
    }

    private static func words(_ command: String) -> [String] {
        TurkishText.folded(command).split { !$0.isLetter }.map(String.init)
    }
}
