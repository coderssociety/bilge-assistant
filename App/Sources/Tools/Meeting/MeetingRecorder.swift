import AsistanCore
import Foundation
import Observation

/// A meeting being recorded: from "toplantıyı kaydetmeye başla" to "kaydı bitir", everything heard is
/// transcribed by Whisper and kept here as timestamped text. No audio is kept, and nothing is captured outside
/// a recording.
@MainActor
@Observable
final class MeetingRecorder {
    struct Recording: Sendable {
        let startedAt: Date
        let duration: TimeInterval
        let chunks: [TranscriptChunk]
    }

    private(set) var startedAt: Date?
    private(set) var chunks: [TranscriptChunk] = []

    var isRecording: Bool { startedAt != nil }

    func begin(at now: Date = .now) {
        startedAt = now
        chunks = []
    }

    /// Speech `duration` seconds long that ended at `end`.
    func append(_ text: String, duration: TimeInterval, endingAt end: Date = .now) {
        guard let startedAt else { return }
        let offset = max(0, end.timeIntervalSince(startedAt) - duration)
        chunks = chunks + [TranscriptChunk(offset: offset, text: text)]
    }

    func finish(at now: Date = .now) -> Recording? {
        guard let startedAt else { return nil }
        let recording = Recording(startedAt: startedAt, duration: now.timeIntervalSince(startedAt), chunks: chunks)
        self.startedAt = nil
        chunks = []
        return recording
    }
}
