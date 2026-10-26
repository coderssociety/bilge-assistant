import Foundation

/// The user's voice, from a few enrolled recordings: speaker embeddings (L2-normalized) whose mean
/// is compared with what is heard.
public struct VoicePrint: Codable, Equatable, Sendable {
    public static let minimumRecordings = 3

    public let embeddings: [[Float]]

    public init?(embeddings: [[Float]]) {
        guard embeddings.count >= Self.minimumRecordings, let dimension = embeddings.first?.count, dimension > 0,
              embeddings.allSatisfy({ $0.count == dimension }) else { return nil }
        self.embeddings = embeddings
    }

    /// The mean embedding, normalized.
    public var centroid: [Float] {
        Self.mean(of: embeddings)
    }

    /// Cosine similarity with the enrolled voice, from -1 to 1.
    public func score(_ embedding: [Float]) -> Float {
        Self.cosine(centroid, Self.normalized(embedding))
    }

    /// Calibrated on synthetic voices: own 0.82-0.91, the closest other voice at most 0.72.
    public static let thresholdRange: ClosedRange<Float> = 0.55...0.75
    /// Room below the weakest enrolled recording, for a voice that is tired, distant or noisy.
    private static let thresholdMargin: Float = 0.08

    /// A threshold for this voice: just under how well each recording matches the others (each
    /// scored against the mean of the rest), kept within `thresholdRange`.
    public var suggestedThreshold: Float {
        let leaveOneOut = embeddings.indices.map { index in
            var others = embeddings
            others.remove(at: index)
            return Self.cosine(Self.mean(of: others), embeddings[index])
        }
        let weakest = leaveOneOut.min() ?? Self.thresholdRange.upperBound
        return min(max(weakest - Self.thresholdMargin, Self.thresholdRange.lowerBound), Self.thresholdRange.upperBound)
    }

    /// The mean similarity between the recordings: low when they were noisy or not all the same voice.
    public var consistency: Float {
        var total: Float = 0
        var pairs = 0
        for i in embeddings.indices {
            for j in embeddings.indices where j > i {
                total += Self.cosine(embeddings[i], embeddings[j])
                pairs += 1
            }
        }
        return pairs == 0 ? 0 : total / Float(pairs)
    }

    static func cosine(_ a: [Float], _ b: [Float]) -> Float {
        zip(a, b).reduce(0) { $0 + $1.0 * $1.1 }
    }

    private static func mean(of vectors: [[Float]]) -> [Float] {
        let sum = vectors.dropFirst().reduce(vectors[0]) { zip($0, $1).map(+) }
        return normalized(sum)
    }

    private static func normalized(_ vector: [Float]) -> [Float] {
        let norm = max(sqrt(vector.reduce(0) { $0 + $1 * $1 }), 1e-9)
        return vector.map { $0 / norm }
    }
}

public enum SpeakerCheck {
    public enum Decision: Equatable, Sendable {
        case accepted, rejected
        /// Too little speech for a reliable embedding ("Bilge." alone); the command that follows is checked.
        case tooShort
    }

    public static let minimumSeconds = 0.8

    public static func decide(score: Float, seconds: Double, threshold: Float) -> Decision {
        guard seconds >= minimumSeconds else { return .tooShort }
        return score >= threshold ? .accepted : .rejected
    }
}
