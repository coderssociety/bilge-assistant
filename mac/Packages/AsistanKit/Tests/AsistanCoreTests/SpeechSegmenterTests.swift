import Testing
@testable import AsistanCore

@Suite("SpeechSegmenter")
struct SpeechSegmenterTests {
    /// 4 samples per chunk, so each chunk is easy to identify by its fill value.
    let config = SpeechSegmenter.Configuration(
        chunkDuration: 0.25, startThreshold: 0.6, endThreshold: 0.35,
        minSilence: 0.5, preRoll: 0.25, minSpeech: 0.5, maxSegment: 2.0)

    func chunk(_ value: Float) -> [Float] { [Float](repeating: value, count: 4) }

    @Test("emits a segment with pre-roll once silence lasts long enough")
    func basicSegment() {
        var segmenter = SpeechSegmenter(configuration: config)
        let probabilities: [Float] = [0.1, 0.1, 0.9, 0.9, 0.8, 0.1, 0.1, 0.1]
        var segments: [SpeechSegmenter.Segment] = []
        for (index, probability) in probabilities.enumerated() {
            segments += segmenter.process(chunk(Float(index)), probability: probability)
        }
        #expect(segments.count == 1)
        // pre-roll chunk 1, speech 2...4, trailing silence 5...6 that confirmed the end
        #expect(segments[0].samples == [1, 2, 3, 4, 5, 6].flatMap { chunk(Float($0)) })
        #expect(segments[0].endReason == .silence)
    }

    @Test("drops blips shorter than the minimum speech duration")
    func ignoresBlips() {
        var segmenter = SpeechSegmenter(configuration: config)
        var segments: [SpeechSegmenter.Segment] = []
        for probability: Float in [0.9, 0.1, 0.1, 0.1] {
            segments += segmenter.process(chunk(1), probability: probability)
        }
        #expect(segments.isEmpty)
    }

    @Test("hysteresis keeps a segment open through brief dips")
    func hysteresis() {
        var segmenter = SpeechSegmenter(configuration: config)
        var segments: [SpeechSegmenter.Segment] = []
        for probability: Float in [0.9, 0.5, 0.9, 0.4, 0.9, 0.1, 0.1] {
            segments += segmenter.process(chunk(1), probability: probability)
        }
        #expect(segments.count == 1)
        #expect(segments[0].samples.count == 7 * 4)
    }

    @Test("cuts segments that exceed the maximum length")
    func maxLength() {
        var segmenter = SpeechSegmenter(configuration: config)
        var segments: [SpeechSegmenter.Segment] = []
        for _ in 0..<9 {
            segments += segmenter.process(chunk(1), probability: 0.9)
        }
        #expect(segments.count == 1)
        #expect(segments[0].endReason == .maxLength)
        #expect(segmenter.isInSpeech)
    }

    @Test("flush returns an in-progress segment")
    func flush() {
        var segmenter = SpeechSegmenter(configuration: config)
        _ = segmenter.process(chunk(1), probability: 0.9)
        _ = segmenter.process(chunk(2), probability: 0.9)
        #expect(segmenter.flush()?.samples.count == 8)
        #expect(segmenter.flush() == nil)
    }
}
