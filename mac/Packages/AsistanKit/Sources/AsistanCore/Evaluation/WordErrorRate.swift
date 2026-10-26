public struct WordErrorRate: Sendable, Equatable {
    public let errors: Int
    public let referenceWordCount: Int

    public var rate: Double {
        referenceWordCount == 0 ? (errors == 0 ? 0 : 1) : Double(errors) / Double(referenceWordCount)
    }

    /// Both sides are spoken-normalized first so "14:30" and "on dört otuz" count as the same words.
    public static func compute(reference: String, hypothesis: String, language: AssistantLanguage = .turkish) -> WordErrorRate {
        let referenceWords = words(reference, language: language)
        let hypothesisWords = words(hypothesis, language: language)
        return WordErrorRate(
            errors: FuzzyText.levenshtein(referenceWords, hypothesisWords),
            referenceWordCount: referenceWords.count)
    }

    public static func aggregate(_ results: [WordErrorRate]) -> Double {
        let words = results.reduce(0) { $0 + $1.referenceWordCount }
        let errors = results.reduce(0) { $0 + $1.errors }
        return words == 0 ? 0 : Double(errors) / Double(words)
    }

    private static func words(_ text: String, language: AssistantLanguage) -> [String] {
        TurkishText.normalized(SpokenText.normalize(text, language: language))
            .split(separator: " ")
            .map(String.init)
    }
}
