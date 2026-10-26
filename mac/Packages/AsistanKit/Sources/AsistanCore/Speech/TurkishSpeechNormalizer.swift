import Foundation

/// Rewrites model output into plain spoken Turkish before TTS: digits, times, dates, symbols and markdown.
public enum TurkishSpeechNormalizer {
    private static let suffix = #"(?:['’](\p{L}+))?"#
    private static let maxReadableDigits = 15

    public static func normalize(_ text: String) -> String {
        var result = SpokenText.withoutMarkup(text)
        result = replaceDates(result)
        result = replaceTimes(result)
        result = replace(#"%\s?(?=\d)"#, in: result) { _ in "yüzde " }
        result = replace(#"\s?°\s?C?\b|\s?°"#, in: result) { _ in " derece" }
        result = replace(#"\s?₺|\s?\bTL\b"#, in: result) { _ in " lira" }
        result = replace(#"\s?\$"#, in: result) { _ in " dolar" }
        result = replace(#"\s?€"#, in: result) { _ in " avro" }
        result = replace(#"\b\d{1,3}(?:\.\d{3})+\b"#, in: result) { $0[0]?.replacingOccurrences(of: ".", with: "") }
        result = replace(#"\b(\d+),(\d+)\b"# + suffix, in: result) { groups in
            guard let whole = groups[1].flatMap(Int.init), let fraction = groups[2] else { return nil }
            return TurkishNumberWords.cardinal(whole) + " virgül "
                + TurkishNumberWords.digitsPreservingLeadingZeros(Substring(fraction)) + (groups[3] ?? "")
        }
        result = replace(#"\b(\d+)\b"# + suffix, in: result) { groups in
            guard let digits = groups[1] else { return nil }
            return readInteger(digits) + (groups[2] ?? "")
        }
        return result
            .replacingOccurrences(of: #"[ \t]{2,}"#, with: " ", options: .regularExpression)
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private static func replaceDates(_ text: String) -> String {
        replace(#"\b(\d{1,2})\.(\d{1,2})\.(\d{4})\b"# + suffix, in: text) { groups in
            guard let day = groups[1].flatMap(Int.init), let month = groups[2].flatMap(Int.init),
                  let year = groups[3].flatMap(Int.init), (1...31).contains(day), (1...12).contains(month)
            else { return nil }
            return [TurkishNumberWords.cardinal(day), TurkishNumberWords.monthNames[month - 1],
                    TurkishNumberWords.cardinal(year)].joined(separator: " ") + (groups[4] ?? "")
        }
    }

    private static func replaceTimes(_ text: String) -> String {
        replace(#"\b([01]?\d|2[0-3])[:.]([0-5]\d)\b"# + suffix, in: text) { groups in
            guard let hour = groups[1].flatMap(Int.init), let minutes = groups[2] else { return nil }
            let minuteWords = minutes == "00" ? "" : " " + TurkishNumberWords.digitsPreservingLeadingZeros(Substring(minutes))
            return TurkishNumberWords.cardinal(hour) + minuteWords + (groups[3] ?? "")
        }
    }

    private static func readInteger(_ digits: String) -> String {
        guard digits.count <= maxReadableDigits, let value = Int(digits) else {
            return digits.map { TurkishNumberWords.cardinal(Int(String($0)) ?? 0) }.joined(separator: " ")
        }
        return TurkishNumberWords.cardinal(value)
    }

    /// Replaces each match with `transform(groups)`; returning nil keeps the original match.
    private static func replace(_ pattern: String, in text: String, _ transform: ([String?]) -> String?) -> String {
        guard let regex = try? NSRegularExpression(pattern: pattern) else {
            assertionFailure("Invalid regex: \(pattern)")
            return text
        }
        let source = text as NSString
        var result = text
        for match in regex.matches(in: text, range: NSRange(location: 0, length: source.length)).reversed() {
            let groups = (0..<match.numberOfRanges).map { index -> String? in
                let range = match.range(at: index)
                return range.location == NSNotFound ? nil : source.substring(with: range)
            }
            guard let replacement = transform(groups), let range = Range(match.range, in: result) else { continue }
            result.replaceSubrange(range, with: replacement)
        }
        return result
    }
}
