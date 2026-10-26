import Foundation

/// A word of a spoken command, folded for matching and kept as said for names.
struct SpokenToken {
    let folded: String
    /// The word as said without the suffix after its apostrophe: "Radio'yu" → "Radio", "Medyascope'un" → "Medyascope".
    let stem: String

    static func split(_ text: String) -> [SpokenToken] {
        text.split(whereSeparator: \.isWhitespace).compactMap { raw in
            let word = String(raw).trimmingCharacters(in: .punctuationCharacters.subtracting(["'", "’"]))
            let folded = TurkishText.folded(word)
            guard !folded.isEmpty else { return nil }
            let stem = word.split(whereSeparator: { $0 == "'" || $0 == "’" }).first.map(String.init) ?? word
            return SpokenToken(folded: folded, stem: stem)
        }
    }
}
