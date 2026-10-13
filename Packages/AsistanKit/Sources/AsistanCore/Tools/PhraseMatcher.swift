/// Finds the stored title a spoken phrase refers to ("süt almayı" → "Süt al", "Ahmet" → "Ahmet Yılmaz"),
/// tolerating Turkish case suffixes and extra or missing words.
public enum PhraseMatcher {
    public static let minimumScore = 0.6
    private static let maxSuffixLength = 4
    private static let stopWords: Set<String> = ["ve", "ile", "bir", "bu", "su", "icin", "de", "da", "the"]

    public static func bestMatch(for query: String, in titles: [String]) -> String? {
        let queryWords = words(query)
        guard !queryWords.isEmpty else { return nil }
        var best: (title: String, score: Double)?
        for title in titles {
            let score = score(queryWords, words(title))
            if score > (best?.score ?? 0) { best = (title, score) }
        }
        guard let best, best.score >= minimumScore else { return nil }
        return best.title
    }

    private static func words(_ text: String) -> [String] {
        TurkishText.folded(text).split(separator: " ").map(String.init).filter { !stopWords.contains($0) }
    }

    private static func score(_ query: [String], _ title: [String]) -> Double {
        guard !title.isEmpty else { return 0 }
        let matched = title.filter { titleWord in query.contains { matches($0, titleWord) } }.count
        guard matched > 0 else { return 0 }
        let shorter = Double(min(query.count, title.count))
        let longer = Double(max(query.count, title.count))
        return 0.7 * min(1, Double(matched) / shorter) + 0.3 * Double(matched) / longer
    }

    private static func matches(_ lhs: String, _ rhs: String) -> Bool {
        if lhs == rhs { return true }
        let (short, long) = lhs.count <= rhs.count ? (lhs, rhs) : (rhs, lhs)
        if short.count >= 2, long.hasPrefix(short), long.count - short.count <= maxSuffixLength { return true }
        return short.count >= 4 && FuzzyText.similarity(short, long) >= 0.8
    }
}
