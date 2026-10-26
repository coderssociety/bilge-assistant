import Foundation

/// One transcribed stretch of a recording, `offset` seconds after it began.
public struct TranscriptChunk: Equatable, Sendable {
    public let offset: TimeInterval
    public let text: String

    public init(offset: TimeInterval, text: String) {
        self.offset = offset
        self.text = text
    }
}

/// The Markdown file a meeting or audio transcription is saved as: a summary, then the transcript with a
/// timestamp per chunk.
public struct MeetingNotes: Equatable, Sendable {
    public let title: String
    /// The transcribed file's name; nil for a live recording.
    public let source: String?
    public let duration: TimeInterval
    public let summary: String?
    public let chunks: [TranscriptChunk]
    public let language: AssistantLanguage

    public init(title: String, source: String? = nil, duration: TimeInterval, summary: String?, chunks: [TranscriptChunk],
                language: AssistantLanguage) {
        self.title = title
        self.source = source
        self.duration = duration
        self.summary = summary
        self.chunks = chunks
        self.language = language
    }

    /// "00:05", "12:40", "1:02:03".
    public static func timestamp(_ offset: TimeInterval) -> String {
        let total = max(0, Int(offset.rounded(.down)))
        let (hours, minutes, seconds) = (total / 3600, total % 3600 / 60, total % 60)
        if hours > 0 { return String(format: "%d:%02d:%02d", hours, minutes, seconds) }
        return String(format: "%02d:%02d", minutes, seconds)
    }

    /// "[00:05] text" per chunk, the form the summarizer reads.
    public static func transcriptLines(_ chunks: [TranscriptChunk]) -> [String] {
        chunks.map { "[\(timestamp($0.offset))] \($0.text)" }
    }

    /// "2026-10-25 14.30": sorts by date, and Finder shows no colons.
    public static func fileName(for date: Date, calendar: Calendar = .current) -> String {
        let parts = calendar.dateComponents([.year, .month, .day, .hour, .minute], from: date)
        return String(format: "%04d-%02d-%02d %02d.%02d", parts.year ?? 0, parts.month ?? 0, parts.day ?? 0,
                      parts.hour ?? 0, parts.minute ?? 0)
    }

    public var markdown: String {
        let english = language == .english
        let length = "\(english ? "Length" : "Süre"): \(Self.timestamp(duration))"
        let details = source.map { "\(english ? "Source" : "Kaynak"): \($0) · \(length)" } ?? length
        var lines = ["# \(title)", "", details]
        lines += ["", "## \(english ? "Summary" : "Özet")", ""]
        lines.append(summary?.trimmingCharacters(in: .whitespacesAndNewlines).nilIfEmpty
            ?? (english ? "_No summary could be written._" : "_Özet yazılamadı._"))
        lines += ["", "## \(english ? "Transcript" : "Döküm")", ""]
        for chunk in chunks {
            lines += ["**[\(Self.timestamp(chunk.offset))]** \(chunk.text)", ""]
        }
        return lines.joined(separator: "\n")
    }
}

private extension String {
    var nilIfEmpty: String? { isEmpty ? nil : self }
}
