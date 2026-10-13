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
    private static let units: [(pattern: NSRegularExpression, seconds: Double)] = [
        (try! NSRegularExpression(pattern: #"(\d+)(\s+buçuk)?\s+saat"#), 3600),
        (try! NSRegularExpression(pattern: #"(\d+)(\s+buçuk)?\s+dakika"#), 60),
        (try! NSRegularExpression(pattern: #"(\d+)(\s+buçuk)?\s+saniye"#), 1),
    ]

    private static let fractionsOfHour: [(pattern: NSRegularExpression, seconds: Double)] = [
        (try! NSRegularExpression(pattern: #"(?<!\p{L})yarım\s+saat"#, options: .caseInsensitive), 1800),
        (try! NSRegularExpression(pattern: #"(?<!\p{L})çeyrek\s+saat"#, options: .caseInsensitive), 900),
    ]

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
}
