import Foundation

/// Spoken lengths of time: "1 saat 5 dakika", "2 hours 1 minute".
public enum SpokenDuration {
    public static func text(minutes: Int, language: AssistantLanguage) -> String {
        let (hours, rest) = (max(minutes, 0) / 60, max(minutes, 0) % 60)
        if language == .english {
            if hours == 0, rest == 0 { return "less than a minute" }
            let parts = [hours > 0 ? plural(hours, "hour") : nil, rest > 0 ? plural(rest, "minute") : nil]
            return parts.compactMap { $0 }.joined(separator: " ")
        }
        if hours == 0, rest == 0 { return "bir dakikadan az" }
        let parts = [hours > 0 ? "\(hours) saat" : nil, rest > 0 ? "\(rest) dakika" : nil]
        return parts.compactMap { $0 }.joined(separator: " ")
    }

    /// Said after an answer from the cache when no source could be reached.
    public static func staleNote(age: TimeInterval, language: AssistantLanguage) -> String {
        let since = text(minutes: Int(age / 60), language: language)
        return language == .english
            ? " I couldn't get fresh data; this is from \(since) ago."
            : " Güncel veriye ulaşamadım; bu bilgi \(since) önceki."
    }

    private static func plural(_ count: Int, _ unit: String) -> String {
        "\(count) \(unit)\(count == 1 ? "" : "s")"
    }
}
