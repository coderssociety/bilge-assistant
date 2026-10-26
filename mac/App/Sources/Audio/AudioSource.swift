@preconcurrency import AVFoundation

/// 16 kHz mono samples plus the host time of the first one, so echo cancellation can line the
/// microphone up with what the speaker was playing at that moment.
struct AudioChunk: Sendable {
    let samples: [Float]
    let hostTime: UInt64

    var startSeconds: Double { AVAudioTime.seconds(forHostTime: hostTime) }
}

/// Where the assistant's 16 kHz mono input comes from: the microphone, or scripted audio in tests.
@MainActor
protocol AudioSource: AnyObject {
    func requestPermission() async -> Bool
    func start() throws -> AsyncStream<AudioChunk>
    func stop()
}

extension MicrophoneCapture: AudioSource {
    func requestPermission() async -> Bool {
        await Self.requestPermission()
    }
}

/// Plays pre-recorded 16 kHz samples into the pipeline at real-time pace. With `echo`, the
/// assistant's own playback is mixed back in (delayed and attenuated) like a laptop speaker would.
@MainActor
final class ScriptedAudioSource: AudioSource {
    struct Echo: Sendable {
        let timeline: PlaybackTimeline
        let delay: Double
        let gain: Float
    }

    private nonisolated static let bufferSamples = 1600
    private let samples: [Float]
    private let echo: Echo?
    private var task: Task<Void, Never>?

    init(samples: [Float], echo: Echo? = nil) {
        self.samples = samples
        self.echo = echo
    }

    func requestPermission() async -> Bool { true }

    func start() throws -> AsyncStream<AudioChunk> {
        let (stream, continuation) = AsyncStream<AudioChunk>.makeStream()
        let samples = samples
        let echo = echo
        let interval = Duration.seconds(Double(Self.bufferSamples) / StreamingResampler.targetSampleRate)
        task = Task.detached {
            let clock = ContinuousClock()
            var deadline = clock.now
            for start in stride(from: 0, to: samples.count, by: Self.bufferSamples) {
                if Task.isCancelled { break }
                var chunk = Array(samples[start..<min(start + Self.bufferSamples, samples.count)])
                // Like a real microphone: a chunk is delivered once captured, so it began a chunk ago.
                let captureStart = AVAudioTime.seconds(forHostTime: mach_absolute_time())
                    - Double(chunk.count) / StreamingResampler.targetSampleRate
                let hostTime = AVAudioTime.hostTime(forSeconds: captureStart)
                if let echo {
                    let heard = echo.timeline.samples(from: captureStart - echo.delay, count: chunk.count)
                    for index in chunk.indices { chunk[index] += heard[index] * echo.gain }
                }
                continuation.yield(AudioChunk(samples: chunk, hostTime: hostTime))
                deadline += interval
                try? await clock.sleep(until: deadline)
            }
            continuation.finish()
        }
        return stream
    }

    func stop() {
        task?.cancel()
        task = nil
    }
}
