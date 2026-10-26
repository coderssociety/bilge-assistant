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

    /// "10:00'da", "11:00'de", "13:00'te", "15:40'ta": the ending follows the last number as spoken
    /// (the minutes, or the hour on the hour).
    public static func timeLocative(hour: Int, minute: Int) -> String {
        let spoken = minute > 0 ? minute : hour
        let lastWordEnding: String = switch (spoken % 10, spoken / 10 % 10) {
        case (1, _), (2, _), (7, _), (8, _): "de"
        case (3, _), (4, _), (5, _): "te"
        case (6, _), (9, _): "da"
        case (0, 0): "da"
        case (0, 2), (0, 5): "de"
        case (0, 4): "ta"
        default: "da"
        }
        return String(format: "%02d:%02d'", hour, minute) + lastWordEnding
    }
}
