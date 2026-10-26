import AsistanCore
import Foundation

/// "Yalnızca benim sesime yanıt ver" (only answer my voice): checks that a command was spoken by the enrolled voice.
/// Off until a voice is enrolled and the user turns it on.
@MainActor
final class SpeakerGate {
    let verifier = SpeakerVerifier()
    let store: VoiceprintStore
    private let settings: AssistantSettings

    init(store: VoiceprintStore, settings: AssistantSettings) {
        self.store = store
        self.settings = settings
    }

    var isActive: Bool { settings.speakerCheckEnabled && store.stored != nil }

    /// Loads the model ahead of the first command, so the check adds no wait then.
    func prepare() {
        guard isActive else { return }
        Task { try? await verifier.prepare() }
    }

    /// When the check cannot run (model missing, error) the speech is let through: a broken check
    /// must not lock the user out. It is logged.
    func check(_ samples: [Float]) async -> SpeakerCheck.Decision {
        guard let stored = store.stored else { return .accepted }
        let seconds = Double(samples.count) / StreamingResampler.targetSampleRate
        guard seconds >= SpeakerCheck.minimumSeconds else { return .tooShort }
        do {
            let embedding = try await verifier.embedding(of: samples)
            let score = stored.voicePrint.score(embedding)
            let decision = SpeakerCheck.decide(score: score, seconds: seconds, threshold: stored.threshold)
            Log.wake.info("Speaker score \(score, format: .fixed(precision: 2)) (threshold \(stored.threshold, format: .fixed(precision: 2)))")
            return decision
        } catch {
            Log.wake.error("Speaker check failed, letting speech through: \(error.localizedDescription, privacy: .public)")
            return .accepted
        }
    }
}
