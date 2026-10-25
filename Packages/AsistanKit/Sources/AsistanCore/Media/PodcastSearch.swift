import Foundation

/// A podcast as the iTunes Search API lists it (`media=podcast`).
public struct PodcastShow: Sendable, Equatable {
    public let name: String
    public let artist: String
    public let feedURL: URL

    public init(name: String, artist: String, feedURL: URL) {
        self.name = name
        self.artist = artist
        self.feedURL = feedURL
    }
}

/// Which search result is the podcast that was named.
public enum PodcastSearch {
    private struct Response: Decodable {
        let results: [Result]?
    }

    private struct Result: Decodable {
        let collectionName: String?
        let artistName: String?
        let feedUrl: String?
    }

    /// The results that have a feed over http(s), in the API's order of relevance.
    public static func shows(from data: Data) -> [PodcastShow] {
        guard let response = try? JSONDecoder().decode(Response.self, from: data) else { return [] }
        return (response.results ?? []).compactMap { result in
            guard let name = result.collectionName?.trimmingCharacters(in: .whitespacesAndNewlines), !name.isEmpty,
                  let feed = result.feedUrl.flatMap({ URL(string: $0) }),
                  ["http", "https"].contains(feed.scheme?.lowercased() ?? "") else { return nil }
            return PodcastShow(name: name, artist: result.artistName ?? "", feedURL: feed)
        }
    }

    /// The show named exactly so, else the first whose name holds the whole phrase, else the first whose name or
    /// host has every word said. Nil when none does, rather than playing an unrelated podcast.
    public static func best(_ shows: [PodcastShow], for query: String) -> PodcastShow? {
        let wanted = TurkishText.folded(query)
        guard !wanted.isEmpty else { return nil }
        let names = shows.map { TurkishText.folded($0.name) }
        if let exact = names.firstIndex(of: wanted) { return shows[exact] }
        if let phrase = names.firstIndex(where: { (" " + $0 + " ").contains(" " + wanted + " ") }) { return shows[phrase] }
        let words = wanted.split(separator: " ")
        return shows.first { show in
            let said = Set(TurkishText.folded(show.name + " " + show.artist).split(separator: " "))
            return words.allSatisfy(said.contains)
        }
    }
}

public enum PodcastEpisodes {
    /// The newest item with audio: the latest dated one when the feed gives dates, else the first in the feed.
    public static func latest(_ items: [RSSHeadlines.Item]) -> RSSHeadlines.Item? {
        let episodes = items.filter { $0.enclosure != nil }
        let dated = episodes.filter { $0.published != nil }
        return dated.max { ($0.published ?? .distantPast) < ($1.published ?? .distantPast) } ?? episodes.first
    }

    /// Whole calendar days from `date` to `now`: 0 for today, 1 for yesterday.
    public static func daysSince(_ date: Date, now: Date, calendar: Calendar = .current) -> Int {
        let days = calendar.dateComponents([.day], from: calendar.startOfDay(for: date), to: calendar.startOfDay(for: now)).day ?? 0
        return max(0, days)
    }
}
