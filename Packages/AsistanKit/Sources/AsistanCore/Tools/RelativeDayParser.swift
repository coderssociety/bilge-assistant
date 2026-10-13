import Foundation

/// Reads which day a Turkish request refers to ("yarın", "cuma", "haftaya çarşamba", "3 gün sonra")
/// as an offset from today. A bare weekday means its next occurrence; today's weekday means next week.
public enum RelativeDayParser {
    private static let fixed: [(phrase: String, offset: Int)] = [
        ("obur gun", 2), ("ertesi gun", 1), ("yarin", 1), ("bugun", 0),
    ]
    /// Calendar weekday numbers (1 = Sunday).
    private static let weekdays: [String: Int] = [
        "pazar": 1, "pazartesi": 2, "sali": 3, "carsamba": 4, "persembe": 5, "cuma": 6, "cumartesi": 7,
    ]
    private static let daysLater = try! NSRegularExpression(pattern: #"(\d+) gun sonra"#)

    public static func dayOffset(in text: String, now: Date, calendar: Calendar = .current) -> Int? {
        let folded = TurkishText.folded(text)
        let source = folded as NSString
        if let match = daysLater.firstMatch(in: folded, range: NSRange(location: 0, length: source.length)) {
            return Int(source.substring(with: match.range(at: 1)))
        }
        let words = folded.split(separator: " ").map(String.init)
        for (index, word) in words.enumerated() {
            let stem = weekdays.keys.sorted { $0.count > $1.count }.first { word.hasPrefix($0) }
            guard let stem, let target = weekdays[stem] else { continue }
            let today = calendar.component(.weekday, from: now)
            var offset = (target - today + 7) % 7
            if offset == 0 { offset = 7 }
            let nextWeek = index > 0 && words[index - 1].hasPrefix("haftaya")
            return nextWeek && offset < 7 ? offset + 7 : offset
        }
        return fixed.first { folded.contains($0.phrase) }?.offset
    }
}
