import Foundation

public enum TurkishText {
    private static let turkishLocale = Locale(identifier: "tr_TR")
    private static let apostrophes: Set<Character> = ["'", "’", "‘", "`", "´"]
    private static let diacriticFolds: [Character: Character] = [
        "ç": "c", "ğ": "g", "ı": "i", "ö": "o", "ş": "s", "ü": "u", "â": "a", "î": "i", "û": "u",
    ]

    public static func lowercased(_ text: String) -> String {
        text.lowercased(with: turkishLocale)
    }

    /// Lowercase words separated by single spaces; apostrophes are dropped so "Safari'yi" stays one word.
    public static func normalized(_ text: String) -> String {
        let lowered = lowercased(text)
        let mapped = lowered.compactMap { character -> Character? in
            if apostrophes.contains(character) { return nil }
            return character.isLetter || character.isNumber ? character : " "
        }
        return String(mapped)
            .split(separator: " ", omittingEmptySubsequences: true)
            .joined(separator: " ")
    }

    public static func folded(_ text: String) -> String {
        String(normalized(text).map { diacriticFolds[$0] ?? $0 })
    }
}
