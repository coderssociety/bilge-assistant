import Foundation

/// A command's words as said and folded side by side, so a parser can match folded words and still hand
/// back the user's own spelling: "Ahmet'in", "süt ve yumurta".
struct SpokenWords {
    let raw: [String]
    /// "e-postasına" folds to one word, "epostasina".
    let folded: [String]

    static let questionParticles: Set<String> = [
        "mi", "mu", "misin", "musun", "misiniz", "musunuz", "lutfen", "hemen", "simdi", "please", "now",
    ]
    private static let edgePunctuation = CharacterSet(charactersIn: "\"“”‘’'«».,!?;:…").union(.whitespaces)
    private static let apostrophes: Set<Character> = ["'", "’"]

    init(_ text: String) {
        raw = text.split(whereSeparator: \.isWhitespace).map(String.init)
        folded = raw.map { TurkishText.folded($0).replacingOccurrences(of: " ", with: "") }
    }

    var count: Int { raw.count }

    /// One past the last word that is not a question particle or "lütfen".
    var contentEnd: Int {
        var end = raw.count
        while end > 0, Self.questionParticles.contains(folded[end - 1]) { end -= 1 }
        return end
    }

    /// The said words in `range`, with quotes and punctuation trimmed from both ends.
    func text(_ range: Range<Int>) -> String {
        let clamped = range.clamped(to: 0..<raw.count)
        guard !clamped.isEmpty else { return "" }
        return raw[clamped].joined(separator: " ").trimmingCharacters(in: Self.edgePunctuation)
    }

    /// "ekle:" — the dictated text starts after it.
    func endsWithColon(_ index: Int) -> Bool {
        raw[index].hasSuffix(":")
    }

    /// "Ahmet'in" → ("Ahmet", "in"); nil for a word without an apostrophe.
    func properName(_ index: Int) -> (name: String, suffix: String)? {
        let word = raw[index].trimmingCharacters(in: Self.edgePunctuation)
        guard let mark = word.firstIndex(where: Self.apostrophes.contains) else { return nil }
        let name = String(word[..<mark])
        guard !name.isEmpty else { return nil }
        return (name, TurkishText.folded(String(word[word.index(after: mark)...])))
    }

    /// Whether the said word starts with a capital letter, as names do: "Ahmet Yılmaz'ı".
    func isCapitalized(_ index: Int) -> Bool {
        raw[index].first?.isUppercase == true
    }
}
