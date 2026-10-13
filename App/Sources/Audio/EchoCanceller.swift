import FluidAudio

/// LocalVQE streaming echo cancellation: removes the assistant's own voice from the microphone
/// so the user can be heard while it is talking. Each chunk needs the matching speaker samples.
actor EchoCanceller {
    private let manager: LocalVqeManager
    private var stream: LocalVqeStream

    init() async throws {
        manager = try await LocalVqeManager(config: LocalVqeConfig(chunk: .realtime16ms))
        stream = try await manager.makeStream()
    }

    func process(mic: [Float], reference: [Float]) async throws -> [Float] {
        try await stream.enhance(mic: mic, reference: reference)
    }

    /// Starts a fresh clip; call at every playback start/stop so stale echo state never leaks over.
    func reset() async throws {
        try await stream.reset()
    }
}
