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

    /// On folded text, where "2'de" reads "2de". "1 saat 15 dakika" is a duration, not a quarter past three.
    /// The second group, when present, is "buçuk".
    private static let spokenHours: [(pattern: NSRegularExpression, onlyTwelveHour: Bool)] = [
        (try! NSRegularExpression(pattern: #"(?<!\d )(?<!\p{L})saat (\d{1,2})(?:de|da|te|ta)?( bucuk\p{L}*)?(?![\p{L}\d])(?! (?:dakika|saniye))"#), false),
        (try! NSRegularExpression(pattern: #"(?<![\d\p{L}])(\d{1,2}) (bucuk)(?:ta|te|da|de)(?!\p{L})"#), true),
        (try! NSRegularExpression(pattern: #"(?<![\d\p{L}])(\d{1,2})(?:de|da|te|ta)(?!\p{L})"#), true),
    ]
    private static let noonWords: Set<String> = ["oglen", "ogleyin", "oglende"]

    /// An unpadded clock ("3:15", from "üçü çeyrek geçe") was said on a 12-hour clock, so for appointments
    /// it gets the same afternoon rule as a spoken hour; alarms take the hour as said.
    public static func parse(_ text: String, appointment: Bool = false) -> Result? {
        let source = text as NSString
        let range = NSRange(location: 0, length: source.length)
        if let match = clock.firstMatch(in: text, range: range),
           let hour = Int(source.substring(with: match.range(at: 1))),
           let minute = Int(source.substring(with: match.range(at: 2))) {
            let saidOnTwelveHourClock = match.range(at: 1).length == 1
            let adjusted = appointment && saidOnTwelveHourClock ? appointmentHour(hour, in: TurkishText.folded(text)) : hour
            return Result(hour: adjusted, minute: minute, durationSeconds: nil)
        }
        if appointment, let (hour, minute) = spokenHour(TurkishText.folded(text)) {
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
            return (appointmentHour(hour, in: folded), minute)
        }
        return words.contains(where: { noonWords.contains(String($0)) }) ? (12, 0) : nil
    }

    private static func appointmentHour(_ hour: Int, in folded: String) -> Int {
        let words = folded.split(separator: " ")
        let afternoon = words.contains("aksam") || folded.contains("ogleden sonra")
        let morning = words.contains("sabah") || words.contains("gece")
        return hour < 12 && (afternoon || (!morning && hour <= 6)) ? hour + 12 : hour
    }
}
