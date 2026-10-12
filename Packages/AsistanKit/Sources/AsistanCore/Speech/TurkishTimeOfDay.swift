import Foundation

/// Resolves "akşam 8'de" / "öğleden sonra 3 buçukta" (after digitizing) to 24-hour "20:00'de" / "15:30'da",
/// so the model never has to do the AM/PM arithmetic it gets wrong.
public enum TurkishTimeOfDay {
    private static let pattern = try! NSRegularExpression(
        pattern: #"(?<!\p{L})(sabah|öğleden sonra|öğlen|öğleyin|akşam|gece)\s+(\d{1,2})(?:'(\p{L}+))?(?:\s+buçuk(\p{L}*))?(?!\p{L})"#,
        options: [.caseInsensitive])

    public static func resolve(_ text: String) -> String {
        let source = text as NSString
        var result = text
        for match in pattern.matches(in: text, range: NSRange(location: 0, length: source.length)).reversed() {
            func group(_ index: Int) -> String? {
                let range = match.range(at: index)
                return range.location == NSNotFound ? nil : source.substring(with: range)
            }
            guard let part = group(1).map(TurkishText.lowercased), let hour = group(2).flatMap(Int.init),
                  let hour24 = hour24(hour, partOfDay: part),
                  let range = Range(match.range, in: result)
            else { continue }
            let hasHalf = match.range(at: 4).location != NSNotFound
            let suffix = hasHalf ? softened(group(4) ?? "") : (group(3) ?? "")
            let clock = String(format: "%02d:%02d", hour24, hasHalf ? 30 : 0)
            result.replaceSubrange(range, with: clock + (suffix.isEmpty ? "" : "'" + suffix))
        }
        return result
    }

    private static func hour24(_ hour: Int, partOfDay: String) -> Int? {
        guard (0...12).contains(hour) else { return nil }
        switch partOfDay {
        case "sabah": return hour == 12 ? 0 : hour
        case "öğlen", "öğleyin": return hour == 12 ? 12 : (1...5).contains(hour) ? hour + 12 : hour
        case "öğleden sonra", "akşam": return hour == 12 ? 12 : hour + 12
        case "gece": return hour == 12 ? 0 : (6...11).contains(hour) ? hour + 12 : hour
        default: return nil
        }
    }

    /// "buçukta" ends in a hardened consonant; after "HH:30" ("otuz") the suffix is "da"/"de".
    private static func softened(_ suffix: String) -> String {
        guard let first = suffix.first, first == "t" else { return suffix }
        return "d" + suffix.dropFirst()
    }
}
