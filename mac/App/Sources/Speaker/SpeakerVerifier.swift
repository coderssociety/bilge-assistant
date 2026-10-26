import FluidAudio
import Foundation

/// Speaker embeddings from FluidAudio's CAM++ model (192 values per utterance), downloaded on first use.
actor SpeakerVerifier {
    private var embedder: CampPlusEmbedder?

    func prepare() async throws {
        if embedder == nil { embedder = try await CampPlusEmbedder.load() }
    }

    /// 16 kHz mono samples → L2-normalized embedding.
    func embedding(of samples: [Float]) async throws -> [Float] {
        try await prepare()
        guard let embedder else { throw CancellationError() }
        return try await embedder.embed(audio: samples)
    }
}
