import AsistanCore
import FluidAudio

/// One VAD-sized slice of microphone audio with the model's speech probability for it.
struct VoiceActivityFrame: Sendable {
    enum Event: Sendable { case speechStarted, speechEnded }

    static let duration = Double(VadManager.chunkSize) / Double(VadManager.sampleRate)

    let samples: [Float]
    let probability: Float
    let event: Event?
}

/// Silero VAD over a live stream. Accepts any buffer size and feeds the model exactly `VadManager.chunkSize` samples.
actor VoiceActivityMonitor {
    private let manager: VadManager
    private let segmentation: VadSegmentationConfig
    private var state: VadStreamState
    private var chunker = SampleChunker(chunkSize: VadManager.chunkSize)

    init(segmentation: VadSegmentationConfig = .default) async throws {
        manager = try await VadManager()
        self.segmentation = segmentation
        state = await manager.makeStreamState()
    }

    func process(_ samples: [Float]) async throws -> [VoiceActivityFrame] {
        var frames: [VoiceActivityFrame] = []
        for chunk in chunker.append(samples) {
            let result = try await manager.processStreamingChunk(chunk, state: state, config: segmentation)
            state = result.state
            let event: VoiceActivityFrame.Event? = result.event.map { $0.isStart ? .speechStarted : .speechEnded }
            frames.append(VoiceActivityFrame(samples: chunk, probability: result.probability, event: event))
        }
        return frames
    }

    func reset() async {
        chunker.reset()
        state = await manager.makeStreamState()
    }
}
