import Foundation

/// Deterministically reads "20:00" or "1 saat 15 dakika" from a command that already went through
/// TurkishNumberParser and TurkishTimeOfDay. Used to override the model's guesses for these values.
/// For appointments spoken hours count too: "saat 2'de", "3 buçukta", "10'da", "öğlen".
public enum TimerPhraseParser {
    public struct Result: Sendable, Equatable {
        public let hour: Int?
        public let minute: Int?
        public let durationSeconds: Int?
    }

    private static let clock = try! NSRegularExpression(pattern: #"(?<!\d)([01]?\d|2[0-3]):([0-5]\d)(?!\d)"#)
    private static let units: [(pattern: NSRegularExpression, seconds: Double)] = [
        (try! NSRegularExpression(pattern: #"(\d+)(\s+buçuk)?\s+saat"#), 3600),
        (try! NSRegularExpression(pattern: #"(\d+)(\s+buçuk)?\s+dakika"#), 60),
        (try! NSRegularExpression(pattern: #"(\d+)(\s+buçuk)?\s+saniye"#), 1),
    ]

    private static let fractionsOfHour: [(pattern: NSRegularExpression, seconds: Double)] = [
        (try! NSRegularExpression(pattern: #"(?<!\p{L})yarım\s+saat"#, options: .caseInsensitive), 1800),
        (try! NSRegularExpression(pattern: #"(?<!\p{L})çeyrek\s+saat"#, options: .caseInsensitive), 900),
    ]

    /// On folded text, where "2'de" reads "2de". "1 saat 15 dakika" is a duration, not a quarter past three.
    /// The second group, when present, is "buçuk".
    private static let spokenHours: [(pattern: NSRegularExpression, onlyTwelveHour: Bool)] = [
        (try! NSRegularExpression(pattern: #"(?<!\d )(?<!\p{L})saat (\d{1,2})(?:de|da|te|ta)?( bucuk\p{L}*)?(?![\p{L}\d])(?! (?:dakika|saniye))"#), false),
        (try! NSRegularExpression(pattern: #"(?<![\d\p{L}])(\d{1,2}) (bucuk)(?:ta|te|da|de)(?!\p{L})"#), true),
        (try! NSRegularExpression(pattern: #"(?<![\d\p{L}])(\d{1,2})(?:de|da|te|ta)(?!\p{L})"#), true),
    ]
    private static let noonWords: Set<String> = ["oglen", "ogleyin", "oglende"]

    public static func parse(_ text: String, appointment: Bool = false) -> Result? {
        let source = text as NSString
        let range = NSRange(location: 0, length: source.length)
        if let match = clock.firstMatch(in: text, range: range),
           let hour = Int(source.substring(with: match.range(at: 1))),
           let minute = Int(source.substring(with: match.range(at: 2))) {
            return Result(hour: hour, minute: minute, durationSeconds: nil)
        }
        if appointment, let (hour, minute) = spokenHour(TurkishText.folded(text)) {
            return Result(hour: hour, minute: minute, durationSeconds: nil)
        }
        var total = 0.0
        for unit in units {
            for match in unit.pattern.matches(in: text, range: range) {
                guard let value = Double(source.substring(with: match.range(at: 1))) else { continue }
                let half = match.range(at: 2).location != NSNotFound ? 0.5 : 0
                total += (value + half) * unit.seconds
            }
        }
        for fraction in fractionsOfHour where fraction.pattern.firstMatch(in: text, range: range) != nil {
            total += fraction.seconds
        }
        return total > 0 ? Result(hour: nil, minute: nil, durationSeconds: Int(total)) : nil
    }

    /// Appointments rarely start before 7 in the morning, so a bare "saat 2" is 14:00 unless "sabah" or
    /// "gece" is said; "akşam" and "öğleden sonra" always mean the afternoon half.
    private static func spokenHour(_ folded: String) -> (hour: Int, minute: Int)? {
        let words = folded.split(separator: " ")
        let source = folded as NSString
        let range = NSRange(location: 0, length: source.length)
        for spoken in spokenHours {
            guard let match = spoken.pattern.firstMatch(in: folded, range: range),
                  let hour = Int(source.substring(with: match.range(at: 1))),
                  spoken.onlyTwelveHour ? (1...12).contains(hour) : (0...23).contains(hour)
            else { continue }
            let minute = match.numberOfRanges > 2 && match.range(at: 2).location != NSNotFound ? 30 : 0
            let afternoon = words.contains("aksam") || folded.contains("ogleden sonra")
            let morning = words.contains("sabah") || words.contains("gece")
            let shifted = hour < 12 && (afternoon || (!morning && hour <= 6))
            return (shifted ? hour + 12 : hour, minute)
        }
        return words.contains(where: { noonWords.contains(String($0)) }) ? (12, 0) : nil
    }
}
