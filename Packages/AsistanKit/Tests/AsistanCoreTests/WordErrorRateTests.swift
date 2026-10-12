import Testing
@testable import AsistanCore

@Suite("WordErrorRate")
struct WordErrorRateTests {
    @Test("identical text has zero errors after normalization")
    func identical() {
        let result = WordErrorRate.compute(reference: "Safari'yi aç.", hypothesis: "safariyi aç")
        #expect(result.errors == 0)
        #expect(result.rate == 0)
    }

    @Test("counts substitutions, insertions and deletions")
    func editOperations() {
        let result = WordErrorRate.compute(reference: "sesi biraz kıs lütfen", hypothesis: "sesi kes lütfen hemen")
        // biraz deleted, kıs→kes substituted, hemen inserted
        #expect(result.errors == 3)
        #expect(result.referenceWordCount == 4)
        #expect(result.rate == 0.75)
    }

    @Test("digits and spelled numbers compare equal")
    func numbersNormalized() {
        let result = WordErrorRate.compute(reference: "saat on dört otuzda uyandır", hypothesis: "Saat 14:30'da uyandır.")
        #expect(result.errors == 0)
    }

    @Test("aggregates over a corpus by total reference words")
    func aggregate() {
        let results = [
            WordErrorRate.compute(reference: "bir iki", hypothesis: "bir"),
            WordErrorRate.compute(reference: "üç dört beş altı", hypothesis: "üç dört beş altı"),
        ]
        #expect(WordErrorRate.aggregate(results) == 1.0 / 6.0)
    }
}
