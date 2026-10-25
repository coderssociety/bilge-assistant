import Foundation

public struct EarthquakeQuery: Sendable, Equatable {
    public enum Period: Sendable, Equatable {
        case lastDay, today, yesterday, week
    }

    /// The province named in the request.
    public var province: Province?
    /// "Yakınımda": around the user's city.
    public var nearUser = false
    public var period: Period = .lastDay
    /// Said ("büyük deprem", "5 üzeri"); nil lets the answer pick a sensible floor.
    public var minimumMagnitude: Double?
    /// "En son deprem nerede": only the newest event.
    public var latestOnly = false

    public init(province: Province? = nil, nearUser: Bool = false, period: Period = .lastDay,
                minimumMagnitude: Double? = nil, latestOnly: Bool = false) {
        self.province = province
        self.nearUser = nearUser
        self.period = period
        self.minimumMagnitude = minimumMagnitude
        self.latestOnly = latestOnly
    }
}

/// Recognises questions about earthquakes ("son depremler", "İzmir'de deprem var mı") and reads what they ask.
/// Expects digits for spoken numbers ("dört üzeri" → "4 üzeri").
public enum EarthquakeRequest {
    private static let topicStems = ["deprem", "zelzele", "sarsinti"]
    private static let englishTopicStems = ["earthquake", "quake", "tremor", "seismic"]
    /// Preparedness and general knowledge are for the conversation; reminders and searches for their own tools.
    private static let otherStems = [
        "canta", "sigorta", "dask", "tatbikat", "nedir", "neden", "nasil olusur", "korun", "yapmali", "yapilmali",
        "toplanma", "hatirlat", "not al", "ara ", "google", "haritada", "fay hatti",
    ]
    private static let englishOtherStems = [
        "kit", "insurance", "drill", "what is", "why do", "how do", "prepare", "remind", "note", "search", "google",
        "fault line",
    ]
    static let bigMagnitude = 4.0

    public static func isRequest(_ text: String, language: AssistantLanguage = .turkish) -> Bool {
        let folded = " " + TurkishText.folded(text) + " "
        let (topics, others) = language == .english ? (englishTopicStems, englishOtherStems) : (topicStems, otherStems)
        return topics.contains { folded.contains(" " + $0) } && !others.contains { folded.contains(" " + $0) }
    }

    public static func query(_ text: String, language: AssistantLanguage = .turkish) -> EarthquakeQuery {
        let folded = TurkishText.folded(text)
        let words = folded.split(separator: " ").map(String.init)
        var query = EarthquakeQuery(province: TurkishProvinces.named(in: text))
        if language == .english {
            query.nearUser = ["near me", "nearby", "around here", "close to me", "near us"].contains { folded.contains($0) }
            query.period = englishPeriod(folded)
            query.latestOnly = ["latest", "last earthquake", "last quake", "most recent", "just now", "where was"]
                .contains { folded.contains($0) }
            let big = words.contains { ["big", "strong", "major", "large", "serious"].contains($0) }
            query.minimumMagnitude = threshold(in: folded, pattern: #"(?:above|over|magnitude|than) (\d)"#) ?? (big ? bigMagnitude : nil)
        } else {
            query.nearUser = words.contains { $0.hasPrefix("yakin") || $0.hasPrefix("cevrem") || $0.hasPrefix("buralar") }
                || words.contains("burada") || words.contains("bizde")
            query.period = turkishPeriod(words, folded: folded)
            let singular = words.contains { ["deprem", "depremi", "depremin"].contains($0) }
            query.latestOnly = folded.contains("en son") || folded.contains("az once") || folded.contains("biraz once")
                || words.contains { $0.hasPrefix("nerede") || $0 == "nerde" || $0 == "nereden" }
                || (words.contains("son") && singular)
            let big = words.contains { ["buyuk", "siddetli", "ciddi", "korkutucu", "guclu"].contains($0) }
            let said = threshold(in: folded, pattern: #"(\d) (?:ve )?(?:uzeri|ustu|ten|tan|den|dan|buyuklugunde)"#)
            query.minimumMagnitude = said ?? (big ? bigMagnitude : nil)
        }
        if query.province != nil { query.nearUser = false }
        return query
    }

    private static func turkishPeriod(_ words: [String], folded: String) -> EarthquakeQuery.Period {
        if words.contains(where: { $0.hasPrefix("bugun") }) { return .today }
        if words.contains("dun") || words.contains("dunku") { return .yesterday }
        if folded.contains("bu hafta") || folded.contains("son bir hafta") || folded.contains("son hafta") { return .week }
        return .lastDay
    }

    private static func englishPeriod(_ folded: String) -> EarthquakeQuery.Period {
        if folded.contains("today") { return .today }
        if folded.contains("yesterday") { return .yesterday }
        if folded.contains("this week") || folded.contains("past week") || folded.contains("last week") { return .week }
        return .lastDay
    }

    private static func threshold(in folded: String, pattern: String) -> Double? {
        guard let regex = try? NSRegularExpression(pattern: pattern),
              let match = regex.firstMatch(in: folded, range: NSRange(folded.startIndex..., in: folded)),
              let range = Range(match.range(at: 1), in: folded) else { return nil }
        return Double(folded[range])
    }
}
