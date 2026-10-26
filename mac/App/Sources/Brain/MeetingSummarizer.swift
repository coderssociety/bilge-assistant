import AsistanCore
import Foundation

/// Summarizes a transcript into decisions, action items and open questions: part by part when it is longer
/// than the on-device model's window, then merging the partial summaries.
@MainActor
struct MeetingSummarizer {
    static let maximumSummaryTokens = 500

    let language: AssistantLanguage
    /// Prompt and instructions in, the model's whole reply out.
    let generate: (_ prompt: String, _ instructions: String) async throws -> String

    func summarize(_ chunks: [TranscriptChunk]) async throws -> String? {
        let parts = MeetingSummaryPrompt.parts(of: MeetingNotes.transcriptLines(chunks))
        guard !parts.isEmpty else { return nil }
        let instructions = MeetingSummaryPrompt.instructions(language: language)
        var summaries: [String] = []
        for (index, part) in parts.enumerated() {
            let prompt = MeetingSummaryPrompt.prompt(forPart: part, index: index, count: parts.count, language: language)
            summaries.append(try await generate(prompt, instructions))
        }
        while summaries.count > 1 {
            var merged: [String] = []
            for group in MeetingSummaryPrompt.mergeGroups(summaries) {
                guard group.count > 1 else {
                    merged += group
                    continue
                }
                merged.append(try await generate(MeetingSummaryPrompt.mergePrompt(group, language: language), instructions))
            }
            summaries = merged
        }
        return summaries.first
    }
}
