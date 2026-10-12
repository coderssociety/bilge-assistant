import AsistanCore
import FluidAudio

struct VoiceActivityUpdate: Sendable {
    enum Event: Sendable { case speechStarted, speechEnded }

    let probability: Float
    let event: Event?
}

/// Silero VAD over a live stream. Accepts any buffer size and feeds the model exactly `VadManager.chunkSize` samples.
actor VoiceActivityDetector {
    private let manager: VadManager
    private let segmentation: VadSegmentationConfig
    private var state: VadStreamState
    private var chunker = SampleChunker(chunkSize: VadManager.chunkSize)

    init(segmentation: VadSegmentationConfig = .default) async throws {
        manager = try await VadManager()
        self.segmentation = segmentation
        state = await manager.makeStreamState()
    }

    func process(_ samples: [Float]) async throws -> [VoiceActivityUpdate] {
        var updates: [VoiceActivityUpdate] = []
        for chunk in chunker.append(samples) {
            let result = try await manager.processStreamingChunk(chunk, state: state, config: segmentation)
            state = result.state
            let event: VoiceActivityUpdate.Event? = result.event.map { $0.isStart ? .speechStarted : .speechEnded }
            updates.append(VoiceActivityUpdate(probability: result.probability, event: event))
        }
        return updates
    }

    func reset() async {
        chunker.reset()
        state = await manager.makeStreamState()
    }
}
