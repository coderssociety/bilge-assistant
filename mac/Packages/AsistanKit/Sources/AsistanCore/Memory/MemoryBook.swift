import Foundation

public struct MemoryEntry: Codable, Equatable, Sendable, Identifiable {
    public let id: UUID
    public let text: String
    public let created: Date
}

/// Facts the user asked the assistant to keep ("eşimin adı Ayşe"). Kept small: every entry is part of
/// the conversation instructions, and the on-device model has an 8K window.
public struct MemoryBook: Codable, Equatable, Sendable {
    public enum AddOutcome: Equatable, Sendable {
        case added, duplicate, rejected
        /// Added, and the oldest fact was dropped to make room.
        case addedDroppingOldest
    }

    public static let maxEntries = 50
    public static let maxEntryLength = 200

    public let entries: [MemoryEntry]

    public init(entries: [MemoryEntry] = []) {
        self.entries = entries
    }

    public func adding(_ text: String, at date: Date) -> (MemoryBook, AddOutcome) {
        // One line per fact: a line break inside one could pose as another fact or an instruction.
        let cleaned = text.split(whereSeparator: \.isWhitespace).joined(separator: " ")
            .trimmingCharacters(in: .whitespaces.union(.punctuationCharacters))
        guard !cleaned.isEmpty, cleaned.count <= Self.maxEntryLength else { return (self, .rejected) }
        let key = TurkishText.folded(cleaned)
        guard !entries.contains(where: { TurkishText.folded($0.text) == key }) else { return (self, .duplicate) }
        let kept = entries.suffix(Self.maxEntries - 1)
        let outcome: AddOutcome = kept.count < entries.count ? .addedDroppingOldest : .added
        return (MemoryBook(entries: kept + [MemoryEntry(id: UUID(), text: cleaned, created: date)]), outcome)
    }

    public func removing(matching query: String) -> (book: MemoryBook, removed: MemoryEntry?) {
        guard let entry = entry(matching: query) else { return (self, nil) }
        return (removing(id: entry.id), entry)
    }

    /// The fact `query` refers to ("kahveyle ilgili" → "Kahvemi şekersiz içerim"), nil if none or unclear.
    public func entry(matching query: String) -> MemoryEntry? {
        let text = PhraseMatcher.bestMatch(for: query, in: entries.map(\.text)) ?? stemMatch(for: query)
        return text.flatMap { text in entries.first { $0.text == text } }
    }

    public var latest: MemoryEntry? { entries.last }

    private static let stemLength = 4

    /// "kahveyle" and "kahvemi" share no suffix-tolerant match but the same stem; only a single best entry counts.
    private func stemMatch(for query: String) -> String? {
        let stems = Set(TurkishText.folded(query).split(separator: " ").filter { $0.count >= Self.stemLength }.map { $0.prefix(Self.stemLength) })
        let scored = entries.map { entry in
            (entry.text, TurkishText.folded(entry.text).split(separator: " ").filter { stems.contains($0.prefix(Self.stemLength)) }.count)
        }
        guard let best = scored.max(by: { $0.1 < $1.1 }), best.1 > 0, scored.filter({ $0.1 == best.1 }).count == 1 else { return nil }
        return best.0
    }

    public func removing(id: UUID) -> MemoryBook {
        MemoryBook(entries: entries.filter { $0.id != id })
    }

    /// "- fact" lines, newest first, as many as fit in `maxCharacters`; nil when there is nothing to say.
    public func promptLines(maxCharacters: Int) -> String? {
        var lines: [String] = []
        var used = 0
        for entry in entries.reversed() {
            let line = "- \(entry.text)"
            guard used + line.count <= maxCharacters else { break }
            lines.append(line)
            used += line.count + 1
        }
        return lines.isEmpty ? nil : lines.joined(separator: "\n")
    }
}
