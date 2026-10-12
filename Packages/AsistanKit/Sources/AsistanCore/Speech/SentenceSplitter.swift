import Foundation

/// Splits Turkish text into sentence-sized pieces so speech can start before the whole reply is synthesized.
public enum SentenceSplitter {
    public static let defaultMaxLength = 160

    private static let terminators: Set<Character> = [".", "!", "?", "…"]
    private static let abbreviations: Set<String> = [
        "dr", "prof", "doç", "av", "sn", "vb", "vs", "örn", "bkz", "no", "st", "cad", "sok", "mah", "apt", "yy",
    ]

    public static func split(_ text: String, maxLength: Int = defaultMaxLength) -> [String] {
        var sentences: [String] = []
        var remainder = Substring(text)
        while let boundary = firstBoundary(in: remainder, endCountsAsBoundary: true) {
            sentences.append(String(remainder[..<boundary]))
            remainder = remainder[boundary...]
        }
        return sentences
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
            .flatMap { wrap($0, maxLength: maxLength) }
    }

    /// Index just past the first sentence terminator that is followed by whitespace (or the end, if allowed).
    static func firstBoundary(in text: Substring, endCountsAsBoundary: Bool) -> Substring.Index? {
        var index = text.startIndex
        while index < text.endIndex {
            let character = text[index]
            let next = text.index(after: index)
            if terminators.contains(character) {
                var end = next
                while end < text.endIndex, terminators.contains(text[end]) { end = text.index(after: end) }
                let atEnd = end == text.endIndex
                if (atEnd && endCountsAsBoundary) || (!atEnd && text[end].isWhitespace) {
                    if character != "." || !endsWithAbbreviation(text[..<index]) { return end }
                }
                index = end
                continue
            }
            index = next
        }
        return endCountsAsBoundary && !text.isEmpty ? text.endIndex : nil
    }

    private static func endsWithAbbreviation(_ prefix: Substring) -> Bool {
        let lastWord = prefix.split(whereSeparator: { $0.isWhitespace }).last.map(String.init) ?? ""
        return abbreviations.contains(TurkishText.lowercased(lastWord))
    }

    private static func wrap(_ sentence: String, maxLength: Int) -> [String] {
        guard sentence.count > maxLength else { return [sentence] }
        var parts: [String] = []
        var current = ""
        for clause in sentence.components(separatedBy: ", ") {
            let candidate = current.isEmpty ? clause : current + ", " + clause
            // +1 leaves room for the comma kept at the end of a non-final part.
            if current.isEmpty || candidate.count + 1 <= maxLength {
                current = candidate
            } else {
                parts.append(current + ",")
                current = clause
            }
        }
        if !current.isEmpty { parts.append(current) }
        return parts.flatMap { hardWrap($0, maxLength: maxLength) }
    }

    private static func hardWrap(_ text: String, maxLength: Int) -> [String] {
        guard text.count > maxLength else { return [text] }
        var parts: [String] = []
        var current = ""
        for word in text.split(separator: " ") {
            let candidate = current.isEmpty ? String(word) : current + " " + word
            if candidate.count > maxLength, !current.isEmpty {
                parts.append(current)
                current = String(word)
            } else {
                current = candidate
            }
        }
        if !current.isEmpty { parts.append(current) }
        return parts
    }
}

/// Collects streamed text fragments and releases whole sentences as soon as they are unambiguous.
public struct SentenceAccumulator: Sendable {
    private var buffer = ""
    private let maxLength: Int

    public init(maxLength: Int = SentenceSplitter.defaultMaxLength) {
        self.maxLength = maxLength
    }

    public mutating func append(_ fragment: String) -> [String] {
        buffer += fragment
        var completed: [String] = []
        var remainder = Substring(buffer)
        while let boundary = SentenceSplitter.firstBoundary(in: remainder, endCountsAsBoundary: false) {
            completed.append(String(remainder[..<boundary]))
            remainder = remainder[boundary...]
        }
        buffer = String(remainder)
        return completed.flatMap { SentenceSplitter.split($0, maxLength: maxLength) }
    }

    public mutating func finish() -> [String] {
        defer { buffer = "" }
        return SentenceSplitter.split(buffer, maxLength: maxLength)
    }
}
