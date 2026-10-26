import Foundation

/// Turns one dictated utterance into the text to type after what was typed before: spoken
/// punctuation becomes marks, sentences start with a capital, and pieces are spaced like prose.
public enum DictationText {
    /// Longest phrases first, so "noktalı virgül" is not read as "nokta" + "lı virgül".
    private static let marks: [(String, String)] = [
        ("noktali virgul", ";"), ("soru isareti", "?"), ("unlem isareti", "!"), ("iki nokta", ":"), ("uc nokta", "…"),
        ("tirnak ac", "“"), ("tirnak kapat", "”"), ("parantez ac", "("), ("parantez kapat", ")"),
        ("virgul", ","), ("nokta", "."), ("unlem", "!"), ("tire", "-"),
    ]
    private static let englishMarks: [(String, String)] = [
        ("question mark", "?"), ("exclamation mark", "!"), ("exclamation point", "!"), ("full stop", "."),
        ("open quote", "“"), ("close quote", "”"), ("end quote", "”"), ("open parenthesis", "("),
        ("close parenthesis", ")"), ("semicolon", ";"), ("colon", ":"), ("ellipsis", "…"), ("comma", ","),
        ("period", "."), ("dash", "-"), ("hyphen", "-"),
    ]
    private static let attachesLeft: Set<String> = [",", ".", "?", "!", ":", ";", "…", "”", ")"]
    private static let attachesRight: Set<String> = ["“", "("]
    private static let sentenceEnds: Set<Character> = [".", "?", "!", "…", "\n"]

    public static func format(_ spoken: String, after previous: String?, language: AssistantLanguage = .turkish) -> String {
        let pieces = tokens(spoken, marks: language == .english ? englishMarks : marks)
        var output = ""
        var pendingSpace = false
        for piece in pieces {
            if attachesLeft.contains(piece) {
                output += piece
            } else {
                if pendingSpace { output += " " }
                output += piece
            }
            pendingSpace = !attachesRight.contains(piece)
        }
        output = output.replacingOccurrences(of: "“", with: "\"").replacingOccurrences(of: "”", with: "\"")
        guard let first = output.first else { return "" }
        let startsSentence = previous.map { $0.isEmpty || $0.last.map(sentenceEnds.contains) == true } ?? true
        if startsSentence { output = String(first).uppercased(with: language.locale) + output.dropFirst() }
        let needsSpace = previous.map { !$0.isEmpty && !$0.hasSuffix("\n") && !$0.hasSuffix(" ") } ?? false
        return (needsSpace && !attachesLeft.contains(String(first)) ? " " : "") + output
    }

    /// Words and marks, with spoken punctuation replaced.
    private static func tokens(_ spoken: String, marks: [(String, String)]) -> [String] {
        let words = spoken.split(whereSeparator: \.isWhitespace).map(String.init)
        var result: [String] = []
        var index = 0
        while index < words.count {
            if let (length, mark) = mark(at: index, in: words, marks: marks) {
                result.append(mark)
                index += length
            } else {
                result.append(words[index])
                index += 1
            }
        }
        return result
    }

    private static func mark(at index: Int, in words: [String], marks: [(String, String)]) -> (Int, String)? {
        for (phrase, mark) in marks {
            let parts = phrase.split(separator: " ").map(String.init)
            guard index + parts.count <= words.count else { continue }
            let spoken = words[index..<(index + parts.count)].map { TurkishText.folded($0) }
            if spoken == parts { return (parts.count, mark) }
        }
        return nil
    }
}
