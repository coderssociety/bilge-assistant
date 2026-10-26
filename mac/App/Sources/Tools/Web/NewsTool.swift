import AsistanCore
import Foundation
import FoundationModels
import Synchronization

/// The headlines read out while the app runs, so asking again goes on with the next ones.
final class NewsReading: Sendable {
    private let memory = Mutex(HeadlineMemory())

    func recentTopic() -> NewsRequest.Topic? {
        memory.withLock { $0.recentTopic(at: .now) }.flatMap(NewsRequest.Topic.init(rawValue:))
    }

    func recentSource() -> NewsSource? {
        memory.withLock { $0.recentSource(at: .now) }.flatMap(NewsSource.init(rawValue:))
    }

    func next(_ items: [RSSHeadlines.Item], topic: NewsRequest.Topic, source: NewsSource,
              count: Int) -> HeadlineMemory.Reading {
        memory.withLock { $0.next(items, topic: topic.rawValue, source: source.rawValue, count: count, at: .now) }
    }

    /// The headline just read that `command` points at.
    func article(for command: String) -> NewsArticleReference.Request? {
        let heard = memory.withLock { $0.heardItems(at: .now) }
        return NewsArticleReference.find(command, lastReading: heard.lastReading, all: heard.all)
    }

    /// Only addresses that came with a headline read out are opened.
    func wasRead(_ link: URL) -> Bool {
        memory.withLock { $0.heardItems(at: .now).all.contains { $0.link == link } }
    }
}

struct NewsTool: AssistantTool {
    let name = "news"
    let description = "Son haber başlıklarını okur: gündem, ekonomi, spor, dünya ya da bilim-teknoloji (Anadolu Ajansı, TRT Haber ya da BBC Türkçe)."
    let reading: NewsReading
    private static let headlineCount = 5
    /// Enough of the feed to go on with after the first few.
    private static let feedCount = 30

    @Generable
    enum Category {
        case general, economy, sports, world, technology

        init(_ topic: NewsRequest.Topic) {
            self = switch topic {
            case .general: .general
            case .economy: .economy
            case .sports: .sports
            case .world: .world
            case .technology: .technology
            }
        }

        var topic: NewsRequest.Topic {
            switch self {
            case .general: .general
            case .economy: .economy
            case .sports: .sports
            case .world: .world
            case .technology: .technology
            }
        }

        /// As the feed names it: "bilim-teknoloji", "technology".
        var spokenName: String {
            switch (AppLanguage.current, self) {
            case (_, .general): ""
            case (.turkish, .economy): "ekonomi"
            case (.turkish, .sports): "spor"
            case (.turkish, .world): "dünya"
            case (.turkish, .technology): "bilim-teknoloji"
            case (.english, .economy): "business"
            case (.english, .sports): "sport"
            case (.english, .world): "world"
            case (.english, .technology): "technology"
            }
        }
    }

    @Generable
    struct Arguments {
        @Guide(description: "Haber konusu; belirtilmediyse general")
        var category: Category
        @Guide(description: "Boş bırak")
        var source: String?
    }

    /// A topic or source said in the command wins over the model's choice; "bu kadar mı" goes on with what was
    /// just read, and "başka bir kaynak" turns to the next source.
    func refine(_ arguments: Arguments, command: String) -> Arguments {
        let language = AppLanguage.current
        let continues = NewsRequest.isContinuation(command)
        let topic = NewsRequest.topic(in: command) ?? (continues ? reading.recentTopic() : nil) ?? arguments.category.topic
        let source: NewsSource? = if let named = NewsSource.named(in: command, language: language) {
            named
        } else if NewsSource.asksForAnother(command) {
            (reading.recentSource() ?? .preferred(for: language)).next(for: topic)
        } else {
            continues ? reading.recentSource() : nil
        }
        return Arguments(category: Category(topic), source: source?.rawValue)
    }

    func call(arguments: Arguments) async throws -> String {
        let language = AppLanguage.current
        let source = arguments.source.flatMap(NewsSource.init(rawValue:)).flatMap { $0.language == language ? $0 : nil }
            ?? .preferred(for: language)
        // A source without a feed of its own for the topic gives its general headlines, which the introduction says.
        let category = source.feed(arguments.category.topic) == nil ? Category.general : arguments.category
        guard let url = source.feed(category.topic) else {
            return ToolReply.failure(String(localized: "Haber kaynağı açılamadı."))
        }
        do {
            let feed = RSSHeadlines.items(try await WebFetch.data(from: url), limit: Self.feedCount)
            guard !feed.isEmpty else {
                return ToolReply.failure(String(localized: "Haber başlığı bulunamadı."))
            }
            let read = reading.next(feed, topic: category.topic, source: source, count: Self.headlineCount)
            return Self.introduction(read.kind, category, source)
                + read.headlines.map { $0.hasSuffix(".") ? $0 : $0 + "." }.joined(separator: " ")
        } catch {
            return ToolReply.failure(String(localized: "Haberler alınamadı. \(error.localizedDescription)"))
        }
    }

    private static func introduction(_ kind: HeadlineMemory.Reading.Kind, _ category: Category,
                                     _ source: NewsSource) -> String {
        let topic = category.spokenName
        switch (AppLanguage.current, kind) {
        case (.english, .first):
            return topic.isEmpty ? "Latest headlines \(source.from). " : "Latest \(topic) headlines \(source.from). "
        case (.english, .next):
            return "The next headlines. "
        case (.english, .again):
            return "Nothing new since I last read them; the latest are still these. "
        case (.turkish, .first):
            return topic.isEmpty
                ? String(localized: "\(source.from) son başlıklar. ")
                : String(localized: "\(source.from) son \(topic) başlıkları. ")
        case (.turkish, .next):
            return String(localized: "Sıradaki başlıklar. ")
        case (.turkish, .again):
            return String(localized: "Son okuduğumdan beri yeni başlık yok; en son başlıklar yine şunlar. ")
        }
    }
}

/// "Başka bir kaynak" after the headlines, and "TRT haberleri": the router model takes the first for small talk,
/// so requests for a source are routed by rule to the news.
struct NewsSourceTool: RuleRoutedTool {
    let name = "newsFromSource"
    let description = "Haberleri başka bir kaynaktan ya da söylenen kaynaktan okur."
    let news: NewsTool

    @MainActor
    func claims(_ command: String) -> Bool {
        if NewsSource.asksForAnother(command) { return news.reading.recentTopic() != nil }
        return NewsSource.named(in: command, language: AppLanguage.current) != nil && NewsRequest.namesNews(command)
    }

    func arguments(fromCommand command: String) -> NewsTool.Arguments? {
        news.refine(NewsTool.Arguments(category: .general, source: nil), command: command)
    }

    func call(arguments: NewsTool.Arguments) async throws -> String {
        try await news.call(arguments: arguments)
    }
}
