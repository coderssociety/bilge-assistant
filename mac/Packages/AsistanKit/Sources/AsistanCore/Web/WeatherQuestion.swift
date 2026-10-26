import Foundation

/// What a weather question asks besides the city, read from its own words: which day, which part of it,
/// and whether it is about rain ("akşam yağmur var mı", "yarın sabah hava nasıl").
public enum WeatherQuestion {
    public enum PartOfDay: String, Sendable, CaseIterable {
        case morning, noon, afternoon, evening, night

        /// Local hours covered, as Open-Meteo's hourly forecast indexes them.
        public var hours: Range<Int> {
            switch self {
            case .morning: 6..<12
            case .noon: 11..<14
            case .afternoon: 12..<18
            case .evening: 18..<22
            case .night: 21..<24
            }
        }
    }

    public struct Focus: Equatable, Sendable {
        public let dayOffset: Int?
        public let partOfDay: PartOfDay?
        public let asksAboutRain: Bool

        public init(dayOffset: Int?, partOfDay: PartOfDay?, asksAboutRain: Bool) {
            self.dayOffset = dayOffset
            self.partOfDay = partOfDay
            self.asksAboutRain = asksAboutRain
        }
    }

    private static let turkishParts: [(prefix: String, part: PartOfDay)] = [
        ("ogleden", .afternoon), ("sabah", .morning), ("ogle", .noon), ("aksam", .evening),
    ]
    /// Whole words: "geçen" (last) folds to "gecen".
    private static let turkishNightWords: Set<String> = ["gece", "geceleyin", "gecesi"]
    private static let englishParts: [String: PartOfDay] = [
        "morning": .morning, "noon": .noon, "midday": .noon, "afternoon": .afternoon, "evening": .evening,
        "tonight": .evening, "night": .night,
    ]
    private static let rainPrefixes = ["yagmur", "yagis", "yagacak", "yagar", "saganak", "semsiye", "rain", "snow", "shower", "umbrella"]

    /// A rain question or a part of day with no day said is about today; a part of day already over
    /// today ("sabah yağmur var mı" in the afternoon) is about tomorrow.
    public static func focus(in command: String, modelDayOffset: Int?, language: AssistantLanguage, now: Date,
                             calendar: Calendar = .current) -> Focus {
        let saidDay = language == .english
            ? EnglishTimeParser.dayOffset(in: command, now: now, calendar: calendar)
            : RelativeDayParser.dayOffset(in: command, now: now, calendar: calendar)
        let words = TurkishText.folded(command).split(separator: " ").map(String.init)
        let part = partOfDay(words, language: language)
        let rain = words.contains { word in word == "kar" || rainPrefixes.contains(where: word.hasPrefix) }
        var day = saidDay ?? modelDayOffset
        if day == nil, rain || part != nil { day = 0 }
        if saidDay == nil, day == 0, let part, calendar.component(.hour, from: now) >= part.hours.upperBound { day = 1 }
        return Focus(dayOffset: day, partOfDay: part, asksAboutRain: rain)
    }

    private static func partOfDay(_ words: [String], language: AssistantLanguage) -> PartOfDay? {
        if language == .english { return words.lazy.compactMap { englishParts[$0] }.first }
        for word in words {
            if let match = turkishParts.first(where: { word.hasPrefix($0.prefix) }) { return match.part }
            if turkishNightWords.contains(word) { return .night }
        }
        return nil
    }
}

/// The city of the last weather answer, so "peki yarın?" right after "İzmir'de hava nasıl" stays in İzmir.
public struct WeatherFollowUp: Sendable {
    public static let window: TimeInterval = 5 * 60

    private var last: (city: String, at: Date)?

    public init() {}

    public mutating func remember(city: String, at now: Date) {
        last = (city, now)
    }

    public func city(at now: Date) -> String? {
        guard let last, now.timeIntervalSince(last.at) < Self.window else { return nil }
        return last.city
    }
}
