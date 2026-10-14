import Foundation
import Testing
@testable import AsistanCore

@Suite("VoicePrint")
struct VoicePrintTests {
    private func unit(_ values: [Float]) -> [Float] {
        let norm = sqrt(values.reduce(0) { $0 + $1 * $1 })
        return values.map { $0 / norm }
    }

    @Test("needs a few consistent recordings of the same length")
    func creation() {
        #expect(VoicePrint(embeddings: [unit([1, 0]), unit([1, 0.1])]) == nil)
        #expect(VoicePrint(embeddings: [unit([1, 0]), unit([1, 0.1]), [1, 0, 0]]) == nil)
        #expect(VoicePrint(embeddings: [unit([1, 0]), unit([1, 0.1]), unit([1, -0.1])]) != nil)
    }

    @Test("scores the enrolled voice above others")
    func scoring() throws {
        let print = try #require(VoicePrint(embeddings: [unit([1, 0.1, 0]), unit([1, -0.1, 0]), unit([1, 0, 0.1])]))
        #expect(print.score(unit([1, 0.05, 0.02])) > 0.95)
        #expect(print.score(unit([0, 1, 0])) < 0.2)
        #expect(print.consistency > 0.95)
    }

    @Test("a check needs enough speech and a score over the threshold")
    func decision() {
        #expect(SpeakerCheck.decide(score: 0.7, seconds: 2, threshold: 0.5) == .accepted)
        #expect(SpeakerCheck.decide(score: 0.3, seconds: 2, threshold: 0.5) == .rejected)
        #expect(SpeakerCheck.decide(score: 0.1, seconds: 0.5, threshold: 0.5) == .tooShort)
    }

    @Test("round-trips through JSON")
    func codable() throws {
        let print = try #require(VoicePrint(embeddings: [unit([1, 0]), unit([1, 0.1]), unit([1, -0.1])]))
        #expect(try JSONDecoder().decode(VoicePrint.self, from: JSONEncoder().encode(print)) == print)
    }

    @Test("the threshold follows how alike the recordings are, within bounds")
    func threshold() throws {
        let tight = try #require(VoicePrint(embeddings: [unit([1, 0.05, 0]), unit([1, -0.05, 0]), unit([1, 0, 0.05]), unit([1, 0, -0.05])]))
        #expect(tight.suggestedThreshold == VoicePrint.thresholdRange.upperBound)
        let loose = try #require(VoicePrint(embeddings: [unit([1, 0.9, 0]), unit([1, -0.9, 0]), unit([1, 0, 0.9]), unit([1, 0, -0.9])]))
        #expect(loose.suggestedThreshold < tight.suggestedThreshold)
        #expect(VoicePrint.thresholdRange.contains(loose.suggestedThreshold))
    }
}
