import AsistanCore
import Foundation
import Observation

/// Records the user reading a few commands and turns them into a voice print. Only embeddings are
/// kept; the recordings are discarded.
@MainActor
@Observable
final class VoiceEnrollment {
    enum Phase: Equatable {
        case ready
        case recording
        case finished(consistency: Float)
        case failed(String)
    }

    static let prompts = [
        "Bilge, saat kaç?", "Bilge, yarın hava nasıl olacak?", "Bilge, müziği biraz kıs.",
        "Bilge, bugün takvimimde ne var?", "Bilge, Ahmet'e geç kalacağımı yaz.",
    ]
    private static let recordingSeconds = 3.5
    /// Below this the recordings do not sound like one voice: noise, distance or someone else speaking.
    private static let minimumConsistency: Float = 0.45

    private(set) var phase: Phase = .ready
    private(set) var index = 0
    private var embeddings: [[Float]] = []
    private let gate: SpeakerGate
    private let settings: AssistantSettings

    init(gate: SpeakerGate, settings: AssistantSettings) {
        self.gate = gate
        self.settings = settings
    }

    var prompt: String { Self.prompts[min(index, Self.prompts.count - 1)] }

    func recordNext() async {
        guard phase == .ready, index < Self.prompts.count else { return }
        phase = .recording
        do {
            let samples = try await Self.record(seconds: Self.recordingSeconds)
            embeddings.append(try await gate.verifier.embedding(of: samples))
            index += 1
            if index < Self.prompts.count {
                phase = .ready
            } else {
                try finish()
            }
        } catch {
            phase = .failed(error.localizedDescription)
        }
    }

    func restart() {
        embeddings = []
        index = 0
        phase = .ready
    }

    private func finish() throws {
        guard let voicePrint = VoicePrint(embeddings: embeddings) else { throw CocoaError(.featureUnsupported) }
        guard voicePrint.consistency >= Self.minimumConsistency else {
            phase = .failed("Kayıtlar birbirine yeterince benzemiyor. Sessiz bir yerde, mikrofona yakın tekrar dener misin?")
            return
        }
        try gate.store.save(voicePrint)
        settings.speakerCheckEnabled = true
        gate.prepare()
        phase = .finished(consistency: voicePrint.consistency)
    }

    private static func record(seconds: Double) async throws -> [Float] {
        let microphone = MicrophoneCapture()
        let stream = try microphone.start()
        defer { microphone.stop() }
        let wanted = Int(seconds * StreamingResampler.targetSampleRate)
        var samples: [Float] = []
        for await chunk in stream {
            samples += chunk.samples
            if samples.count >= wanted { break }
        }
        return samples
    }
}
