/// Resolves a spoken application name ("hesap makinesini", "spotifay") to an installed app.
public struct AppNameMatcher: Sendable {
    public struct App: Sendable, Equatable {
        public let id: String
        public let names: [String]

        public init(id: String, names: [String]) {
            self.id = id
            self.names = names
        }
    }

    public static let minimumScore = 0.72
    private static let maxSuffixLength = 4
    private static let noiseWords: Set<String> = ["uygulamasi", "uygulamasini", "uygulama", "programi", "programini", "app", "application", "the"]

    private let entries: [(app: App, keys: [String])]

    public init(apps: [App]) {
        entries = apps.map { app in
            (app, app.names.map { TurkishText.folded($0) }.filter { !$0.isEmpty })
        }
    }

    public func bestMatch(for query: String) -> App? {
        let words = TurkishText.folded(query).split(separator: " ").map(String.init)
            .filter { !Self.noiseWords.contains($0) }
        let key = words.joined(separator: " ")
        guard !key.isEmpty else { return nil }

        var best: (app: App, score: Double)?
        for entry in entries {
            let score = entry.keys.map { Self.score(query: key, name: $0) }.max() ?? 0
            if score > (best?.score ?? 0) { best = (entry.app, score) }
        }
        guard let best, best.score >= Self.minimumScore else { return nil }
        return best.app
    }

    private static func score(query: String, name: String) -> Double {
        if query == name { return 1 }
        // Turkish case suffixes: "safariyi", "hesap makinesini", "muzigi" (final consonant softening).
        let extra = query.count - name.count
        if (1...maxSuffixLength).contains(extra) {
            let stem = String(query.prefix(name.count))
            let stemScore = FuzzyText.similarity(stem, name)
            if stemScore >= 0.8 { return 0.95 * stemScore }
        }
        var best = FuzzyText.similarity(query, name)
        // A single distinctive word of a multi-word name ("word" → "microsoft word").
        let nameWords = name.split(separator: " ").map(String.init)
        if nameWords.count > 1, !query.contains(" "), nameWords.contains(query), query.count >= 4 {
            best = max(best, 0.9)
        }
        return best
    }
}
