import Foundation

/// English output for the synthesizer: markup removed and symbols spelled out. The synthesizer reads
/// English numbers itself, so digits are left alone.
public enum EnglishSpeechNormalizer {
    public static func normalize(_ text: String) -> String {
        var result = SpokenText.withoutMarkup(text)
        let words: [(String, String)] = [
            (#"(?<=\d)\s?%"#, " percent"),
            (#"\s?°\s?C\b"#, " degrees Celsius"),
            (#"\s?°\s?F\b"#, " degrees Fahrenheit"),
            (#"\s?°"#, " degrees"),
            (#"\s?₺|\s?\bTL\b"#, " lira"),
        ]
        for (pattern, replacement) in words {
            result = result.replacingOccurrences(of: pattern, with: replacement, options: .regularExpression)
        }
        return result
            .replacingOccurrences(of: #"[ \t]{2,}"#, with: " ", options: .regularExpression)
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }
}
