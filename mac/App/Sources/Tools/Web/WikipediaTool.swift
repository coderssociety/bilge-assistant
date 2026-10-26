import AsistanCore
import Foundation
import FoundationModels
import Synchronization

/// "Mustafa Kemal Atatürk kimdir", "fotosentez nedir", "Everest hakkında bilgi ver". Not offered to the router
/// model: the route guard turns a conversation turn into this one only for a clearly encyclopedic question.
/// The summary is untrusted text and only answered, briefly, by the tool-less session.
struct WikipediaTool: AssistantTool {
    let name = "wikipedia"
    let description = "Vikipedi'den bir kişi, yer ya da kavram hakkında kısa bilgi verir."
    let answersWithLanguageModel = true
    private static let maxCharacters = 1200
    private static let searchResults = 3
    private static let cache = Mutex(TimedCache<String, String>(lifetime: 60 * 60))

    @Generable
    struct Arguments {
        @Guide(description: "Kullanıcının isteği, olduğu gibi")
        var command: String
    }

    func arguments(fromCommand command: String) -> Arguments? {
        Arguments(command: command)
    }

    func call(arguments: Arguments) async throws -> String {
        let language = AppLanguage.current
        guard let subject = EncyclopediaQuestion.subject(in: arguments.command, language: language) else {
            return ToolReply.failure(String(localized: "Ne hakkında bilgi istediğini anlayamadım."))
        }
        let host = language == .english ? "en.wikipedia.org" : "tr.wikipedia.org"
        let key = host + "|" + TurkishText.folded(subject)
        if let kept = Self.cache.withLock({ $0.fresh(key, at: .now) }) { return kept }
        do {
            guard let page = try await Self.page(for: subject, host: host) else {
                return ToolReply.failure(String(localized: "Vikipedi'de \(subject) hakkında bir sayfa bulamadım."))
            }
            let material = WikipediaParser.material(page, maxCharacters: Self.maxCharacters, language: language)
            Self.cache.withLock { $0.store(material, for: key, at: .now) }
            return material
        } catch {
            return ToolReply.failure(String(localized: "Vikipedi'ye ulaşamadım. \(error.localizedDescription)"))
        }
    }

    /// The page titled as said, else the first search result that is an article rather than a disambiguation page.
    private static func page(for subject: String, host: String) async throws -> WikipediaParser.Page? {
        let direct = try await summary(of: subject, host: host)
        if let direct, !direct.isDisambiguation { return direct }
        var search = URLComponents(string: "https://\(host)/w/api.php")!
        search.queryItems = [
            .init(name: "action", value: "opensearch"), .init(name: "search", value: subject),
            .init(name: "limit", value: String(searchResults)), .init(name: "namespace", value: "0"), .init(name: "format", value: "json"),
        ]
        let titles = WikipediaParser.openSearchTitles(try await WebFetch.data(from: search.url!))
        for title in titles where title != direct?.title {
            if let page = try await summary(of: title, host: host), !page.isDisambiguation { return page }
        }
        return nil
    }

    private static func summary(of title: String, host: String) async throws -> WikipediaParser.Page? {
        guard let url = URL(string: "https://\(host)/api/rest_v1/page/summary/\(WikipediaParser.titlePath(title))") else { return nil }
        do {
            return WikipediaParser.summary(try await WebFetch.data(from: url))
        } catch WebFetchError.badStatus(404) {
            return nil
        }
    }
}
