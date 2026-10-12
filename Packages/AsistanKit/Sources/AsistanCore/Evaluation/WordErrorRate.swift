public struct WordErrorRate: Sendable, Equatable {
    public let errors: Int
    public let referenceWordCount: Int

    public var rate: Double {
        referenceWordCount == 0 ? (errors == 0 ? 0 : 1) : Double(errors) / Double(referenceWordCount)
    }

    /// Both sides are spoken-normalized first so "14:30" and "on dört otuz" count as the same words.
    public static func compute(reference: String, hypothesis: String) -> WordErrorRate {
        let referenceWords = words(reference)
        let hypothesisWords = words(hypothesis)
        return WordErrorRate(
            errors: editDistance(referenceWords, hypothesisWords),
            referenceWordCount: referenceWords.count)
    }

    public static func aggregate(_ results: [WordErrorRate]) -> Double {
        let words = results.reduce(0) { $0 + $1.referenceWordCount }
        let errors = results.reduce(0) { $0 + $1.errors }
        return words == 0 ? 0 : Double(errors) / Double(words)
    }

    private static func words(_ text: String) -> [String] {
        TurkishText.normalized(TurkishSpeechNormalizer.normalize(text))
            .split(separator: " ")
            .map(String.init)
    }

    private static func editDistance(_ lhs: [String], _ rhs: [String]) -> Int {
        guard !lhs.isEmpty else { return rhs.count }
        guard !rhs.isEmpty else { return lhs.count }
        var previous = Array(0...rhs.count)
        for (i, left) in lhs.enumerated() {
            var current = [i + 1] + Array(repeating: 0, count: rhs.count)
            for (j, right) in rhs.enumerated() {
                let substitution = previous[j] + (left == right ? 0 : 1)
                current[j + 1] = min(substitution, previous[j + 1] + 1, current[j] + 1)
            }
            previous = current
        }
        return previous[rhs.count]
    }
}
