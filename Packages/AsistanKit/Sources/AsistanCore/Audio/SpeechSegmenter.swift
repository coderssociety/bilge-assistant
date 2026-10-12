/// Turns a stream of (audio chunk, speech probability) pairs into complete utterances,
/// with pre-roll so the first syllable is not clipped and hysteresis so short dips don't split words.
public struct SpeechSegmenter: Sendable {
    public struct Configuration: Sendable {
        public var chunkDuration: Double
        public var startThreshold: Float
        public var endThreshold: Float
        public var minSilence: Double
        public var preRoll: Double
        public var minSpeech: Double
        public var maxSegment: Double

        public init(chunkDuration: Double, startThreshold: Float = 0.6, endThreshold: Float = 0.35,
                    minSilence: Double = 0.7, preRoll: Double = 0.5, minSpeech: Double = 0.3, maxSegment: Double = 12) {
            precondition(chunkDuration > 0 && endThreshold <= startThreshold, "Invalid segmenter configuration")
            self.chunkDuration = chunkDuration
            self.startThreshold = startThreshold
            self.endThreshold = endThreshold
            self.minSilence = minSilence
            self.preRoll = preRoll
            self.minSpeech = minSpeech
            self.maxSegment = maxSegment
        }
    }

    public struct Segment: Sendable, Equatable {
        public enum EndReason: Sendable, Equatable { case silence, maxLength, flushed }
        public let samples: [Float]
        public let endReason: EndReason
    }

    public let configuration: Configuration
    private var history: [[Float]] = []
    private var current: [[Float]] = []
    private var speechChunks = 0
    private var silentChunks = 0
    public private(set) var isInSpeech = false

    public init(configuration: Configuration) {
        self.configuration = configuration
    }

    private var preRollChunks: Int { Int((configuration.preRoll / configuration.chunkDuration).rounded()) }
    private var minSilenceChunks: Int { max(1, Int((configuration.minSilence / configuration.chunkDuration).rounded())) }
    private var minSpeechChunks: Int { max(1, Int((configuration.minSpeech / configuration.chunkDuration).rounded())) }
    private var maxSegmentChunks: Int { max(1, Int((configuration.maxSegment / configuration.chunkDuration).rounded())) }

    public mutating func process(_ chunk: [Float], probability: Float) -> [Segment] {
        guard isInSpeech else {
            if probability >= configuration.startThreshold {
                isInSpeech = true
                current = Array(history.suffix(preRollChunks)) + [chunk]
                history.removeAll()
                speechChunks = 1
                silentChunks = 0
            } else {
                remember(chunk)
            }
            return []
        }

        current.append(chunk)
        if probability >= configuration.endThreshold {
            speechChunks += 1
            silentChunks = 0
        } else {
            silentChunks += 1
        }

        if silentChunks >= minSilenceChunks {
            return finishSegment(reason: .silence).map { [$0] } ?? []
        }
        if current.count >= maxSegmentChunks {
            let segment = Segment(samples: current.flatMap { $0 }, endReason: .maxLength)
            current.removeAll()
            speechChunks = 0
            silentChunks = 0
            return [segment]
        }
        return []
    }

    public mutating func flush() -> Segment? {
        guard isInSpeech, !current.isEmpty else { return nil }
        return finishSegment(reason: .flushed)
    }

    public mutating func reset() {
        history.removeAll()
        current.removeAll()
        speechChunks = 0
        silentChunks = 0
        isInSpeech = false
    }

    private mutating func finishSegment(reason: Segment.EndReason) -> Segment? {
        let isLongEnough = speechChunks >= minSpeechChunks
        let samples = current.flatMap { $0 }
        isInSpeech = false
        history = Array(current.suffix(preRollChunks))
        current.removeAll()
        speechChunks = 0
        silentChunks = 0
        return isLongEnough ? Segment(samples: samples, endReason: reason) : nil
    }

    private mutating func remember(_ chunk: [Float]) {
        history.append(chunk)
        if history.count > preRollChunks { history.removeFirst(history.count - preRollChunks) }
    }
}
