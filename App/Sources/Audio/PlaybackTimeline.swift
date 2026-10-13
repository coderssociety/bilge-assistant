import Synchronization

/// What the speaker played, at 16 kHz, keyed by host time — the echo-cancellation reference.
/// Written from the player's render tap thread, read from the microphone pipeline.
final class PlaybackTimeline: Sendable {
    static let sampleRate = 16_000.0
    private static let retentionSeconds = 8.0

    private struct Segment {
        let start: Double
        let samples: [Float]
        var end: Double { start + Double(samples.count) / PlaybackTimeline.sampleRate }
    }

    private let segments = Mutex<[Segment]>([])

    /// Host time up to which rendered audio has been recorded (render taps arrive slightly late).
    var coveredUntil: Double {
        segments.withLock { $0.last?.end ?? 0 }
    }

    func append(_ samples: [Float], startSeconds: Double) {
        guard !samples.isEmpty else { return }
        segments.withLock { segments in
            segments.append(Segment(start: startSeconds, samples: samples))
            let cutoff = startSeconds - Self.retentionSeconds
            segments.removeAll { $0.end < cutoff }
        }
    }

    /// Samples played during [start, start + count/16 kHz); silence where nothing was playing.
    func samples(from start: Double, count: Int) -> [Float] {
        var output = [Float](repeating: 0, count: count)
        let end = start + Double(count) / Self.sampleRate
        segments.withLock { segments in
            for segment in segments where segment.end > start && segment.start < end {
                let sourceOffset = max(0, Int(((start - segment.start) * Self.sampleRate).rounded()))
                let targetOffset = max(0, Int(((segment.start - start) * Self.sampleRate).rounded()))
                let length = min(segment.samples.count - sourceOffset, count - targetOffset)
                guard length > 0 else { continue }
                for index in 0..<length {
                    output[targetOffset + index] = segment.samples[sourceOffset + index]
                }
            }
        }
        return output
    }

    func clear() {
        segments.withLock { $0.removeAll() }
    }
}
