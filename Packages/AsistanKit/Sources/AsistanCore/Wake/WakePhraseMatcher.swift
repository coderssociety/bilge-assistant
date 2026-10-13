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
    /// Room for Turkish vocative/possessive endings: "asistanım", "bilgeciğim".
    private static let maxSuffixLength = 5
    /// One misspelled letter in a short word is another common word ("bilge" → "bilgi"),
    /// so wake phrases this short must be spelled exactly (suffixes still allowed).
    private static let exactMatchMaxLength = 5

    private let phraseKey: String
    private let phraseFillers: [String]
    public let minimumSimilarity: Double

    public init(phrase: String, minimumSimilarity: Double = defaultMinimumSimilarity) {
        let words = TurkishText.folded(phrase).split(separator: " ").map(String.init)
        // A leading filler inside the configured phrase ("Hey Defne") is optional when spoken.
        let leading = words.prefix(while: { Self.fillers.contains($0) })
        let core = words.dropFirst(leading.count)
        phraseFillers = Array(leading)
        let key = (core.isEmpty ? words : Array(core)).joined()
        phraseKey = key
        self.minimumSimilarity = key.count <= Self.exactMatchMaxLength ? 1 : minimumSimilarity
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
        var best = FuzzyText.similarity(candidate, phraseKey)
        let extra = candidate.count - phraseKey.count
        if (1...Self.maxSuffixLength).contains(extra) {
            best = max(best, FuzzyText.similarity(String(candidate.prefix(phraseKey.count)), phraseKey))
        }
        return best
    }

    private static func trimLeadingPunctuation(_ text: String) -> String {
        String(text.drop(while: { $0.isPunctuation || $0.isWhitespace }))
    }
}
