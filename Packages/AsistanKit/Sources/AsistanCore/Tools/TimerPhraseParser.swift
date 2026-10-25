import Foundation

/// Deterministically reads "20:00" or "1 saat 15 dakika" from a command that already went through
/// TurkishNumberParser and TurkishTimeOfDay. Used to override the model's guesses for these values.
public enum TimerPhraseParser {
    public struct Result: Sendable, Equatable {
        public let hour: Int?
        public let minute: Int?
        public let durationSeconds: Int?
    }

    private static let clock = try! NSRegularExpression(pattern: #"(?<!\d)([01]?\d|2[0-3]):([0-5]\d)(?!\d)"#)
    /// The digitizer leaves "bir buçuk" as words.
    private static let units: [(pattern: NSRegularExpression, seconds: Double)] = [
        (try! NSRegularExpression(pattern: #"(\d+|(?<!\p{L})bir)(\s+buçuk)?\s+saat"#, options: .caseInsensitive), 3600),
        (try! NSRegularExpression(pattern: #"(\d+|(?<!\p{L})bir)(\s+buçuk)?\s+dakika"#, options: .caseInsensitive), 60),
        (try! NSRegularExpression(pattern: #"(\d+|(?<!\p{L})bir)(\s+buçuk)?\s+saniye"#, options: .caseInsensitive), 1),
    ]

    private static let halfHour = try! NSRegularExpression(pattern: #"(?<!\p{L})yarım\s+saat"#, options: .caseInsensitive)
    /// "çeyrek saat" is 15 minutes and "3 çeyrek" 45; a bare "çeyrek" may be a leftover of a clock time.
    private static let quarters = try! NSRegularExpression(
        pattern: #"(?<!\p{L})(?:(\d+)\s+)?çeyrek(?!\p{L})(\s+saat)?"#, options: .caseInsensitive)

    public static func parse(_ text: String) -> Result? {
        let source = text as NSString
        let range = NSRange(location: 0, length: source.length)
        if let match = clock.firstMatch(in: text, range: range),
           let hour = Int(source.substring(with: match.range(at: 1))),
           let minute = Int(source.substring(with: match.range(at: 2))) {
            return Result(hour: hour, minute: minute, durationSeconds: nil)
        }
        var total = 0.0
        for unit in units {
            for match in unit.pattern.matches(in: text, range: range) {
                let number = source.substring(with: match.range(at: 1))
                guard let value = Double(number) ?? (TurkishText.lowercased(number) == "bir" ? 1 : nil) else { continue }
                let half = match.range(at: 2).location != NSNotFound ? 0.5 : 0
                total += (value + half) * unit.seconds
            }
        }
        if halfHour.firstMatch(in: text, range: range) != nil { total += 1800 }
        for match in quarters.matches(in: text, range: range) {
            let count = match.range(at: 1).location != NSNotFound ? Double(source.substring(with: match.range(at: 1))) : nil
            if let count {
                total += count * 900
            } else if match.range(at: 2).location != NSNotFound {
                total += 900
            }
        }
        return total > 0 ? Result(hour: nil, minute: nil, durationSeconds: Int(total)) : nil
    }
}
