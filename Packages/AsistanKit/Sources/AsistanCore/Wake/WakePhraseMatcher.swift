/// Finds a spoken wake phrase at the start of a transcript, tolerating ASR misspellings,
/// split words ("a sistan") and Turkish suffixes ("asistanım").
public struct WakePhraseMatcher: Sendable {
    public struct Match: Sendable, Equatable {
        public let command: String
        public let similarity: Double
    }

    public static let defaultMinimumSimilarity = 0.75
    private static let fillers: Set<String> = ["hey", "hay", "ey", "hu", "selam", "merhaba", "sey", "alo", "ya"]
    private static let maxLeadingFillers = 2
    private static let maxTokensPerPhrase = 3
    private static let maxSuffixLength = 3

    private let phraseKey: String
    private let phraseFillers: [String]
    public let minimumSimilarity: Double

    public init(phrase: String, minimumSimilarity: Double = defaultMinimumSimilarity) {
        let words = TurkishText.folded(phrase).split(separator: " ").map(String.init)
        // A leading filler inside the configured phrase ("Hey Defne") is optional when spoken.
        let leading = words.prefix(while: { Self.fillers.contains($0) })
        let core = words.dropFirst(leading.count)
        phraseFillers = Array(leading)
        phraseKey = (core.isEmpty ? words : Array(core)).joined()
        self.minimumSimilarity = minimumSimilarity
    }

    public func match(_ transcript: String) -> Match? {
        guard !phraseKey.isEmpty else { return nil }
        let tokens = transcript.split(whereSeparator: \.isWhitespace)
            .map { (original: String($0), key: TurkishText.folded(String($0))) }
            .filter { !$0.key.isEmpty }

        var best: (end: Int, similarity: Double)?
        for start in 0...min(Self.maxLeadingFillers, tokens.count) {
            if start > 0, !isFiller(tokens[start - 1].key) { break }
            for length in 1...Self.maxTokensPerPhrase where start + length <= tokens.count {
                let candidate = tokens[start..<start + length].map(\.key).joined()
                let similarity = score(candidate)
                if similarity >= minimumSimilarity, similarity > (best?.similarity ?? 0) {
                    best = (start + length, similarity)
                }
            }
        }
        guard let best else { return nil }
        let command = tokens[best.end...].map(\.original).joined(separator: " ")
        return Match(command: Self.trimLeadingPunctuation(command), similarity: best.similarity)
    }

    private func isFiller(_ key: String) -> Bool {
        Self.fillers.contains(key) || phraseFillers.contains(key)
    }

    private func score(_ candidate: String) -> Double {
        var best = Self.similarity(candidate, phraseKey)
        let extra = candidate.count - phraseKey.count
        if (1...Self.maxSuffixLength).contains(extra) {
            best = max(best, Self.similarity(String(candidate.prefix(phraseKey.count)), phraseKey))
        }
        return best
    }

    static func similarity(_ lhs: String, _ rhs: String) -> Double {
        let longest = max(lhs.count, rhs.count)
        guard longest > 0 else { return 1 }
        return 1 - Double(levenshtein(Array(lhs), Array(rhs))) / Double(longest)
    }

    private static func levenshtein(_ lhs: [Character], _ rhs: [Character]) -> Int {
        guard !lhs.isEmpty else { return rhs.count }
        guard !rhs.isEmpty else { return lhs.count }
        var previous = Array(0...rhs.count)
        for (i, left) in lhs.enumerated() {
            var current = [i + 1] + Array(repeating: 0, count: rhs.count)
            for (j, right) in rhs.enumerated() {
                current[j + 1] = min(previous[j] + (left == right ? 0 : 1), previous[j + 1] + 1, current[j] + 1)
            }
            previous = current
        }
        return previous[rhs.count]
    }

    private static func trimLeadingPunctuation(_ text: String) -> String {
        String(text.drop(while: { $0.isPunctuation || $0.isWhitespace }))
    }
}
