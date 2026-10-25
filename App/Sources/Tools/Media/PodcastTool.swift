import AsistanCore
import Foundation
import FoundationModels

/// "Mesele Ekonomi podcastinin son bölümünü aç", "Medyascope'un yeni bölümü var mı". The podcast is found with the
/// iTunes Search API, its feed read for the newest episode, which plays in Bilge's player like the radio; pausing and
/// seeking are media commands. Routed by rule, as the router model would take a show name for music.
struct PodcastTool: RuleRoutedTool {
    let name = "podcast"
    let description = "Adı söylenen podcast'in son bölümünü çalar ya da yeni bölümü olup olmadığını söyler."
    /// Long feeds list the newest episodes first; this much holds dozens of them.
    private static let feedBytes = 1_500_000
    private static let feedItems = 60
    private static let newEpisodeDays = 7

    @Generable
    struct Arguments {
        @Guide(description: "Kullanıcının isteği, olduğu gibi")
        var request: String
    }

    @MainActor
    func claims(_ command: String) -> Bool {
        PodcastRequest.parse(command, language: AppLanguage.current) != nil
    }

    func arguments(fromCommand command: String) -> Arguments? {
        Arguments(request: command)
    }

    func call(arguments: Arguments) async throws -> String {
        let language = AppLanguage.current
        guard let command = PodcastRequest.parse(arguments.request, language: language) else {
            return ToolReply.failure(String(localized: "Hangi podcast'i istediğini anlayamadım."))
        }
        let query = switch command {
        case let .playLatest(show), let .checkNew(show): show
        }
        do {
            guard let show = try await Self.show(named: query, language: language) else {
                return ToolReply.failure(String(localized: "'\(query)' adında bir podcast bulamadım."))
            }
            let feed = try await WebFetch.prefix(from: show.feedURL, maxBytes: Self.feedBytes)
            guard let episode = PodcastEpisodes.latest(RSSHeadlines.items(feed, limit: Self.feedItems)),
                  let audio = episode.enclosure else {
                return ToolReply.failure(String(localized: "\(show.name) podcastinin bölümlerini okuyamadım."))
            }
            if case .checkNew = command { return Self.newEpisodeReply(show: show, episode: episode) }
            await MusicPlayers.pauseAll()
            let started = await StreamPlayer.shared.play(.init(kind: .podcast, title: episode.title, show: show.name, url: audio))
            return started
                ? String(localized: "\(show.name) podcastinin son bölümü çalıyor: \(episode.title).")
                : ToolReply.failure(String(localized: "\(show.name) podcastinin son bölümünü başlatamadım."))
        } catch {
            return ToolReply.failure(String(localized: "Podcast bilgisine ulaşamadım. \(error.localizedDescription)"))
        }
    }

    private static func show(named query: String, language: AssistantLanguage) async throws -> PodcastShow? {
        var components = URLComponents(string: "https://itunes.apple.com/search")!
        components.queryItems = [
            .init(name: "media", value: "podcast"), .init(name: "entity", value: "podcast"), .init(name: "term", value: query),
            .init(name: "country", value: language == .english ? "us" : "tr"), .init(name: "limit", value: "10"),
        ]
        let shows = PodcastSearch.shows(from: try await WebFetch.data(from: components.url!))
        return PodcastSearch.best(shows, for: query)
    }

    private static func newEpisodeReply(show: PodcastShow, episode: RSSHeadlines.Item) -> String {
        guard let published = episode.published else {
            return String(localized: "\(show.name) podcastinin son bölümü: \(episode.title). Ne zaman yayınlandığı belli değil.")
        }
        let days = PodcastEpisodes.daysSince(published, now: .now)
        let when = switch days {
        case 0: String(localized: "bugün")
        case 1: String(localized: "dün")
        default: String(localized: "\(days) gün önce")
        }
        return days <= newEpisodeDays
            ? String(localized: "Evet, \(show.name) podcastinin \(when) yayınlanan yeni bir bölümü var: \(episode.title).")
            : String(localized: "\(show.name) podcastinin son bölümü \(when) yayınlandı: \(episode.title). O zamandan beri yeni bölüm yok.")
    }
}
