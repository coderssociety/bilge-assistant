import Foundation

/// A long text or list a tool read, kept in parts so "devamını oku" goes on where the last part ended
/// instead of reading the start again.
public struct ContinuedReading: Equatable, Sendable {
    public enum Layout: Equatable, Sendable {
        /// Prose, cut at a paragraph, sentence or word end near this many characters.
        case text(maxCharacters: Int)
        /// Items joined by `separator`, this many to a part.
        case list(separator: String, perPart: Int)
    }

    /// After this a follow-up no longer means the reading.
    public static let lifetime: TimeInterval = 15 * 60

    public let parts: [String]
    /// The parts are material a language model answers from, rather than spoken as they are.
    public let answersWithLanguageModel: Bool
    /// The language the reading was asked in ("İngilizce maili Türkçe oku"), so "devamını oku" keeps it.
    public let translation: SpeechLanguage?
    public private(set) var partsRead = 1
    public private(set) var readAt: Date

    /// Nil for a text with nothing to read; without a layout the text is a single part.
    public init?(_ text: String, layout: Layout?, answersWithLanguageModel: Bool, translation: SpeechLanguage? = nil,
                 at date: Date) {
        let parts = layout.map { Self.parts(of: text, layout: $0) } ?? [text]
        guard !parts.isEmpty, !parts[0].isEmpty else { return nil }
        self.parts = parts
        self.answersWithLanguageModel = answersWithLanguageModel
        self.translation = translation
        readAt = date
    }

    public var firstPart: String { parts[0] }
    /// The part read most recently.
    public var lastPart: String { parts[partsRead - 1] }
    public var hasMore: Bool { partsRead < parts.count }

    public func isCurrent(at now: Date) -> Bool {
        now.timeIntervalSince(readAt) < Self.lifetime
    }

    /// The next part, now counted as read; nil when everything has been read.
    public mutating func next(at now: Date) -> String? {
        guard hasMore else { return nil }
        partsRead += 1
        readAt = now
        return lastPart
    }

    public static func parts(of text: String, layout: Layout) -> [String] {
        switch layout {
        case let .text(maxCharacters):
            return textParts(text, maxCharacters: max(1, maxCharacters))
        case let .list(separator, perPart):
            let items = text.components(separatedBy: separator)
            let size = max(1, perPart)
            return stride(from: 0, to: items.count, by: size)
                .map { items[$0..<min($0 + size, items.count)].joined(separator: separator) }
                .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
                .filter { !$0.isEmpty }
        }
    }

    private static func textParts(_ text: String, maxCharacters: Int) -> [String] {
        var parts: [String] = []
        var rest = text[...]
        while let limit = rest.index(rest.startIndex, offsetBy: maxCharacters, limitedBy: rest.endIndex), limit < rest.endIndex {
            let cut = breakPoint(in: rest[..<limit]) ?? limit
            parts.append(String(rest[..<cut]))
            rest = rest[cut...]
        }
        parts.append(String(rest))
        return parts.map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }.filter { !$0.isEmpty }
    }

    /// The last paragraph end in the second half of `window`, else the last sentence end, else the last space.
    private static func breakPoint(in window: Substring) -> String.Index? {
        let tail = window[window.index(window.startIndex, offsetBy: window.count / 2)...]
        if let newline = tail.lastIndex(where: \.isNewline) { return window.index(after: newline) }
        let sentenceEnd = tail.indices.last { index in
            index > tail.startIndex && tail[index].isWhitespace && ".!?…".contains(tail[tail.index(before: index)])
        }
        return sentenceEnd ?? tail.lastIndex(where: \.isWhitespace)
    }
}
