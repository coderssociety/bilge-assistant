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

    func next(_ items: [RSSHeadlines.Item], topic: NewsRequest.Topic, count: Int) -> HeadlineMemory.Reading {
        memory.withLock { $0.next(items, topic: topic.rawValue, count: count, at: .now) }
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
    let description = "Son haber başlıklarını okur: gündem, ekonomi, spor, dünya ya da bilim-teknoloji (Anadolu Ajansı)."
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

        /// Anadolu Ajansı for Turkish, BBC News for English.
        var feedURL: URL? {
            switch AppLanguage.current {
            case .turkish:
                let slug = switch self {
                case .general: "guncel"
                case .economy: "ekonomi"
                case .sports: "spor"
                case .world: "dunya"
                case .technology: "bilim-teknoloji"
                }
                return URL(string: "https://www.aa.com.tr/tr/rss/default?cat=\(slug)")
            case .english:
                let path = switch self {
                case .general: "news/rss.xml"
                case .economy: "news/business/rss.xml"
                case .sports: "sport/rss.xml"
                case .world: "news/world/rss.xml"
                case .technology: "news/technology/rss.xml"
                }
                return URL(string: "https://feeds.bbci.co.uk/\(path)")
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
    }

    /// A topic said in the command wins over the model's choice; "bu kadar mı" goes on with the topic just read.
    func refine(_ arguments: Arguments, command: String) -> Arguments {
        guard let topic = NewsRequest.topic(in: command)
            ?? (NewsRequest.isContinuation(command) ? reading.recentTopic() : nil)
        else { return arguments }
        var refined = arguments
        refined.category = Category(topic)
        return refined
    }

    func call(arguments: Arguments) async throws -> String {
        guard let url = arguments.category.feedURL else {
            return ToolReply.failure(String(localized: "Haber kaynağı açılamadı."))
        }
        do {
            let feed = RSSHeadlines.items(try await WebFetch.data(from: url), limit: Self.feedCount)
            guard !feed.isEmpty else {
                return ToolReply.failure(String(localized: "Haber başlığı bulunamadı."))
            }
            let read = reading.next(feed, topic: arguments.category.topic, count: Self.headlineCount)
            return Self.introduction(read.kind, arguments.category)
                + read.headlines.map { $0.hasSuffix(".") ? $0 : $0 + "." }.joined(separator: " ")
        } catch {
            return ToolReply.failure(String(localized: "Haberler alınamadı. \(error.localizedDescription)"))
        }
    }

    private static func introduction(_ kind: HeadlineMemory.Reading.Kind, _ category: Category) -> String {
        let topic = category.spokenName
        switch (AppLanguage.current, kind) {
        case (.english, .first):
            return topic.isEmpty ? "Latest headlines from BBC News. " : "Latest \(topic) headlines from BBC News. "
        case (.english, .next):
            return "The next headlines. "
        case (.english, .again):
            return "Nothing new since I last read them; the latest are still these. "
        case (.turkish, .first):
            return topic.isEmpty
                ? String(localized: "Anadolu Ajansı'ndan son başlıklar. ")
                : String(localized: "Anadolu Ajansı'ndan son \(topic) başlıkları. ")
        case (.turkish, .next):
            return String(localized: "Sıradaki başlıklar. ")
        case (.turkish, .again):
            return String(localized: "Son okuduğumdan beri yeni başlık yok; en son başlıklar yine şunlar. ")
        }
    }
}
