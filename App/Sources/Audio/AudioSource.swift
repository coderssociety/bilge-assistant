/// Where the assistant's 16 kHz mono input comes from: the microphone, or scripted audio in tests.
@MainActor
protocol AudioSource: AnyObject {
    func requestPermission() async -> Bool
    func start() throws -> AsyncStream<[Float]>
    func stop()
}

extension MicrophoneCapture: AudioSource {
    func requestPermission() async -> Bool {
        await Self.requestPermission()
    }
}

/// Plays pre-recorded 16 kHz samples into the pipeline at real-time pace.
@MainActor
final class ScriptedAudioSource: AudioSource {
    private nonisolated static let bufferSamples = 1600
    private let samples: [Float]
    private var task: Task<Void, Never>?

    init(samples: [Float]) {
        self.samples = samples
    }

    func requestPermission() async -> Bool { true }

    func start() throws -> AsyncStream<[Float]> {
        let (stream, continuation) = AsyncStream<[Float]>.makeStream()
        let samples = samples
        let interval = Duration.seconds(Double(Self.bufferSamples) / StreamingResampler.targetSampleRate)
        task = Task.detached {
            let clock = ContinuousClock()
            var deadline = clock.now
            for start in stride(from: 0, to: samples.count, by: Self.bufferSamples) {
                if Task.isCancelled { break }
                continuation.yield(Array(samples[start..<min(start + Self.bufferSamples, samples.count)]))
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
