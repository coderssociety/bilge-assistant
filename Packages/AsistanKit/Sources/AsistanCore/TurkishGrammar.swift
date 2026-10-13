/// Case suffixes for proper names, following vowel harmony and consonant assimilation.
public enum TurkishGrammar {
    private static let backVowels: Set<Character> = ["a", "ı", "o", "u"]
    private static let frontVowels: Set<Character> = ["e", "i", "ö", "ü"]
    private static let hardConsonants: Set<Character> = ["ç", "f", "h", "k", "p", "s", "ş", "t"]

    /// "İstanbul" → "İstanbul'da", "İzmir" → "İzmir'de", "Paris" → "Paris'te", "Kars" → "Kars'ta".
    public static func locative(_ name: String) -> String {
        let lower = TurkishText.lowercased(name)
        let lastVowel = lower.last { backVowels.contains($0) || frontVowels.contains($0) }
        let vowel = lastVowel.map { backVowels.contains($0) ? "a" : "e" } ?? "e"
        let consonant = lower.last.map { hardConsonants.contains($0) ? "t" : "d" } ?? "d"
        return "\(name)'\(consonant)\(vowel)"
    }
}
