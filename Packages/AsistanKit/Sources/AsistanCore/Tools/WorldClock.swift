import Foundation

/// "Tokyo'da saat kaç", "New York ile aramızda kaç saat fark var", "what time is it in London":
/// answered from a built-in table of places and the system's time zone rules.
public struct WorldClockQuery: Equatable, Sendable {
    public enum Kind: Sendable { case time, difference }

    public let place: WorldPlace
    /// The other side of "X ile Y arasında"; nil compares with the user's own clock.
    public let reference: WorldPlace?
    public let kind: Kind

    private static let turkishQuestionWords: Set<String> = ["kac", "kacti", "ne", "nedir", "kacmis"]
    private static let turkishSuffixes: Set<String> = [
        "da", "de", "ta", "te", "nda", "nde", "daki", "deki", "taki", "teki", "in", "nin", "un", "nun", "yin", "yun",
        "ile", "yla", "yle", "la", "le", "a", "e", "ya", "ye", "na", "ne", "i", "yi", "u", "yu", "dan", "den", "tan",
        "ten", "ndan", "nden", "s",
    ]
    private static let maxQuestionDistance = 3
    private static let placeTable: [(words: [String], place: WorldPlace)] = WorldPlace.all
        .flatMap { place in place.names.map { (words: $0.split(separator: " ").map(String.init), place: place) } }
        .sorted { $0.words.count > $1.words.count }

    public static func parse(_ text: String, language: AssistantLanguage) -> WorldClockQuery? {
        let words = TurkishText.folded(text).split(separator: " ").map(String.init)
        let kind = language == .english ? englishKind(words) : turkishKind(words)
        guard let kind else { return nil }
        let places = places(in: words)
        guard let last = places.last else { return nil }
        return places.count > 1
            ? WorldClockQuery(place: last, reference: places[0], kind: .difference)
            : WorldClockQuery(place: last, reference: nil, kind: kind)
    }

    /// "saat kaç" a few words after "saat", or a "saat farkı".
    private static func turkishKind(_ words: [String]) -> Kind? {
        if words.contains(where: { $0.hasPrefix("fark") }), words.contains(where: { $0.hasPrefix("saat") }) { return .difference }
        for (index, word) in words.enumerated() where word == "saat" || word == "saati" {
            let after = words.dropFirst(index + 1).prefix(maxQuestionDistance)
            if after.contains(where: turkishQuestionWords.contains) { return .time }
        }
        return nil
    }

    /// "time in", "time is it", "Tokyo time", "time difference", "hours ahead".
    private static func englishKind(_ words: [String]) -> Kind? {
        let pairs = Array(zip(words, words.dropFirst()))
        if words.contains("difference") || (words.contains(where: { $0.hasPrefix("hour") })
            && (words.contains("ahead") || words.contains("behind"))) {
            return .difference
        }
        let asksTime = pairs.contains { $0 == "time" && ["in", "there", "now"].contains($1) }
            || zip(words, zip(words.dropFirst(), words.dropFirst(2))).contains { $0 == "time" && $1.0 == "is" && $1.1 == "it" }
            || words.last == "time"
        return asksTime ? .time : nil
    }

    private static func places(in words: [String]) -> [WorldPlace] {
        var found: [WorldPlace] = []
        var index = 0
        while index < words.count {
            let match = placeTable.first { entry in
                guard index + entry.words.count <= words.count else { return false }
                let said = words[index..<index + entry.words.count]
                return zip(said.dropLast(), entry.words.dropLast()).allSatisfy { $0 == $1 }
                    && matches(said[said.endIndex - 1], entry.words[entry.words.count - 1])
            }
            if let match {
                if found.last != match.place { found.append(match.place) }
                index += match.words.count
            } else {
                index += 1
            }
        }
        return found
    }

    private static func matches(_ word: String, _ name: String) -> Bool {
        word == name || (word.hasPrefix(name) && turkishSuffixes.contains(String(word.dropFirst(name.count))))
    }

    public func answer(now: Date, userTimeZone: TimeZone = .current, language: AssistantLanguage) -> String {
        guard let zone = TimeZone(identifier: place.timeZoneIdentifier) else {
            return language == .english ? "I don't know the time zone there." : "Oranın saat dilimini bilmiyorum."
        }
        let referenceZone = reference.flatMap { TimeZone(identifier: $0.timeZoneIdentifier) } ?? userTimeZone
        let minutes = (zone.secondsFromGMT(for: now) - referenceZone.secondsFromGMT(for: now)) / 60
        let clock = Self.clock(now, in: zone, language: language)
        let dayNote = Self.isSameDay(now, zone, referenceZone) ? "" : Self.weekday(now, in: zone, language: language)
        return language == .english
            ? englishAnswer(clock: clock, weekday: dayNote, minutes: minutes)
            : turkishAnswer(clock: clock, weekday: dayNote, minutes: minutes)
    }

    private func turkishAnswer(clock: String, weekday: String, minutes: Int) -> String {
        let clockPart = "saat \(clock)" + (weekday.isEmpty ? "" : ", günlerden \(weekday)")
        let other = reference.map { TurkishGrammar.locative($0.turkishName) + "n" } ?? "senden"
        let span = minutes > 0 ? "\(Self.turkishSpan(minutes)) ileride" : "\(Self.turkishSpan(-minutes)) geride"
        if kind == .difference {
            let gap = minutes == 0
                ? (reference == nil ? "Aramızda saat farkı yok" : "Aralarında saat farkı yok")
                : "\(place.turkishName), \(other) \(span)"
            return "\(gap). Orada \(clockPart)."
        }
        let gap = minutes == 0 ? "Seninle aynı saatte" : "Senden \(span)"
        return "\(TurkishGrammar.locative(place.turkishName)) \(clockPart). \(gap)."
    }

    private func englishAnswer(clock: String, weekday: String, minutes: Int) -> String {
        let clockPart = clock + (weekday.isEmpty ? "" : " on \(weekday)")
        let other = reference?.englishName ?? "you"
        let span = minutes > 0 ? "\(Self.englishSpan(minutes)) ahead of \(other)" : "\(Self.englishSpan(-minutes)) behind \(other)"
        if kind == .difference {
            let name = place.englishName.prefix(1).uppercased() + place.englishName.dropFirst()
            let gap = minutes == 0 ? "There's no time difference" : "\(name) is \(span)"
            return "\(gap); it's \(clockPart) there."
        }
        let gap = minutes == 0 ? "the same as your time" : span
        return "It's \(clockPart) in \(place.englishName), \(gap)."
    }

    /// "6 saat", "2 buçuk saat", "5 saat 45 dakika".
    static func turkishSpan(_ minutes: Int) -> String {
        let (hours, rest) = minutes.quotientAndRemainder(dividingBy: 60)
        switch (hours, rest) {
        case (0, 30): return "yarım saat"
        case (_, 0): return "\(hours) saat"
        case (_, 30): return "\(hours) buçuk saat"
        case (0, _): return "\(rest) dakika"
        default: return "\(hours) saat \(rest) dakika"
        }
    }

    static func englishSpan(_ minutes: Int) -> String {
        let (hours, rest) = minutes.quotientAndRemainder(dividingBy: 60)
        let hourWord = hours == 1 ? "hour" : "hours"
        switch (hours, rest) {
        case (0, 30): return "half an hour"
        case (_, 0): return "\(hours) \(hourWord)"
        case (_, 30): return "\(hours) and a half hours"
        case (0, _): return "\(rest) minutes"
        default: return "\(hours) \(hourWord) \(rest) minutes"
        }
    }

    private static func clock(_ date: Date, in zone: TimeZone, language: AssistantLanguage) -> String {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = zone
        let style = language == .english
            ? Date.FormatStyle(date: .omitted, time: .shortened, locale: language.locale, calendar: calendar, timeZone: zone)
            : Date.FormatStyle(locale: language.locale, calendar: calendar, timeZone: zone)
                .hour(.twoDigits(amPM: .omitted)).minute(.twoDigits)
        return date.formatted(style)
    }

    private static func weekday(_ date: Date, in zone: TimeZone, language: AssistantLanguage) -> String {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = zone
        let name = date.formatted(Date.FormatStyle(locale: language.locale, calendar: calendar, timeZone: zone).weekday(.wide))
        return language == .turkish ? TurkishText.lowercased(name) : name
    }

    private static func isSameDay(_ date: Date, _ first: TimeZone, _ second: TimeZone) -> Bool {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = first
        let one = calendar.dateComponents([.year, .month, .day], from: date)
        calendar.timeZone = second
        return one == calendar.dateComponents([.year, .month, .day], from: date)
    }
}
