import Foundation

/// What a news request asks for, read from its own words: the small router model has answered "teknoloji
/// haberlerinden başlık var mı" with the general headlines.
public enum NewsRequest {
    public enum Topic: String, Sendable, CaseIterable {
        case general, economy, sports, world, technology
    }

    private static let topicWords: [(prefix: String, topic: Topic)] = [
        ("teknoloj", .technology), ("bilim", .technology), ("tech", .technology), ("science", .technology),
        ("ekonom", .economy), ("econom", .economy), ("borsa", .economy), ("piyasa", .economy),
        ("finans", .economy), ("financ", .economy), ("business", .economy),
        ("spor", .sports), ("sport", .sports), ("futbol", .sports), ("football", .sports), ("basketbol", .sports),
        ("dunya", .world), ("world", .world), ("uluslararas", .world), ("international", .world),
        ("gundem", .general),
    ]
    private static let newsWords = ["haber", "baslik", "manset", "gundem", "news", "headline"]

    /// The topic the command names, if it names one.
    public static func topic(in command: String) -> Topic? {
        for word in words(command) {
            if let match = topicWords.first(where: { word.hasPrefix($0.prefix) }) { return match.topic }
        }
        return nil
    }

    /// One folded word naming a topic: "teknoloji", "sporda".
    static func isTopicWord(_ word: String) -> Bool {
        topicWords.contains { word.hasPrefix($0.prefix) }
    }

    /// "Bu kadar mı", "başka var mı": routed to the news without asking for news or naming a topic, it goes on
    /// with the headlines just read.
    public static func isContinuation(_ command: String) -> Bool {
        topic(in: command) == nil && !namesNews(command)
    }

    /// "Haber", "başlık", "news" in any form.
    public static func namesNews(_ command: String) -> Bool {
        words(command).contains { word in newsWords.contains { word.hasPrefix($0) } }
    }

    private static func words(_ command: String) -> [String] {
        TurkishText.folded(command).split { !$0.isLetter }.map(String.init)
    }
}

/// The headlines already read out, so asking again goes on with the next ones instead of repeating them.
public struct HeadlineMemory: Sendable {
    /// After this the news is read from the top again.
    public static let lifetime: TimeInterval = 30 * 60
    /// How long "bu kadar mı" still means the topic just read.
    public static let continuationWindow: TimeInterval = 5 * 60

    public struct Reading: Equatable, Sendable {
        public enum Kind: Sendable {
            /// The latest headlines.
            case first
            /// The ones after those read before.
            case next
            /// Nothing new since the last reading: the same headlines again.
            case again
        }

        public let items: [RSSHeadlines.Item]
        public let kind: Kind

        public var headlines: [String] { items.map(\.title) }

        public init(items: [RSSHeadlines.Item], kind: Kind) {
            self.items = items
            self.kind = kind
        }
    }

    private var read: [String: (titles: Set<String>, at: Date)] = [:]
    private var last: (topic: String, source: String, at: Date)?
    /// What was read out, newest reading first, for "o haberi aç".
    private var heard: [(items: [RSSHeadlines.Item], at: Date)] = []

    public init() {}

    public func recentTopic(at now: Date) -> String? {
        guard let last, now.timeIntervalSince(last.at) < Self.continuationWindow else { return nil }
        return last.topic
    }

    /// Where the headlines just read came from, for "bu kadar mı" and "başka bir kaynak".
    public func recentSource(at now: Date) -> String? {
        guard let last, now.timeIntervalSince(last.at) < Self.continuationWindow, !last.source.isEmpty else { return nil }
        return last.source
    }

    /// The headlines read out within the lifetime: the last reading in its order, then the earlier ones.
    public func heardItems(at now: Date) -> (lastReading: [RSSHeadlines.Item], all: [RSSHeadlines.Item]) {
        let recent = heard.filter { now.timeIntervalSince($0.at) < Self.lifetime }
        return (recent.first?.items ?? [], recent.flatMap(\.items))
    }

    /// The next `count` of `items` (the feed, newest first) not yet read for `topic` from `source`.
    public mutating func next(_ items: [RSSHeadlines.Item], topic: String, source: String = "", count: Int,
                              at now: Date) -> Reading {
        let key = source.isEmpty ? topic : "\(source)/\(topic)"
        let earlier = read[key].flatMap { now.timeIntervalSince($0.at) < Self.lifetime ? $0.titles : nil } ?? []
        let fresh = items.filter { !earlier.contains($0.title) }
        let reading = if fresh.isEmpty {
            Reading(items: Array(items.prefix(count)), kind: .again)
        } else {
            Reading(items: Array(fresh.prefix(count)), kind: earlier.isEmpty ? .first : .next)
        }
        read[key] = ((reading.kind == .again ? [] : earlier).union(reading.headlines), now)
        last = (topic, source, now)
        heard = [(reading.items, now)] + heard.filter { now.timeIntervalSince($0.at) < Self.lifetime }
        return reading
    }
}
