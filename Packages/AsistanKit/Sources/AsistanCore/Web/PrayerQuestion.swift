import Foundation

/// What a prayer-times request asks, read from its words: "akşam ezanı kaçta", "iftara ne kadar var",
/// "yarın imsak kaçta", "bugünkü namaz vakitleri", "when is maghrib". Requests to set an alarm or a
/// reminder around a prayer are not claimed; they go to the timers and reminders as before.
public struct PrayerQuestion: Equatable, Sendable {
    /// How the user named the time, so the answer uses the same word.
    public enum Naming: Sendable { case iftar, sahur }

    public let prayer: Prayer?
    public let naming: Naming?
    public let dayOffset: Int?
    public let listsAll: Bool

    public init(prayer: Prayer?, naming: Naming? = nil, dayOffset: Int? = nil, listsAll: Bool = false) {
        self.prayer = prayer
        self.naming = naming
        self.dayOffset = dayOffset
        self.listsAll = listsAll
    }

    private static let turkishTopics = ["ezan", "namaz", "imsak", "sahur", "iftar", "yatsi", "ikindi"]
    private static let turkishActions = ["hatirlat", "unutma", "alarm", "ekle", "mesaj", "mail", "posta", "uygulama"]
    private static let turkishActionWords: Set<String> = [
        "kur", "kurar", "kursana", "cal", "calar", "calsin", "calsana", "ac", "acar", "acsana",
    ]
    private static let turkishAsks = ["kac", "kaldi", "vakit", "vakt", "saat", "okun", "siradaki", "sonraki", "zaman", "var"]
    /// Earlier entries win: in "bu akşam yatsı kaçta" the evening is when, not which prayer.
    private static let turkishPrayers: [(prefix: String, prayer: Prayer, naming: Naming?)] = [
        ("imsak", .imsak, nil), ("sahur", .imsak, .sahur), ("iftar", .maghrib, .iftar), ("yatsi", .isha, nil),
        ("ikindi", .asr, nil), ("ogle", .dhuhr, nil), ("aksam", .maghrib, nil), ("sabah", .imsak, nil), ("gunes", .sunrise, nil),
    ]

    private static let englishTopics: Set<String> = [
        "prayer", "prayers", "adhan", "azan", "athan", "namaz", "salah", "salat", "fajr", "dhuhr", "zuhr", "asr", "maghrib",
        "isha", "iftar", "suhoor", "suhur", "sehri", "sahur", "imsak", "jummah", "jumuah",
    ]
    private static let englishActions: Set<String> = ["remind", "alarm", "add", "text", "message", "email", "play", "set", "open", "app"]
    private static let englishAsks: Set<String> = ["when", "what", "whats", "how", "until", "till", "time", "times", "next", "left", "schedule", "is"]
    private static let englishPrayers: [String: (prayer: Prayer, naming: Naming?)] = [
        "fajr": (.imsak, nil), "imsak": (.imsak, nil), "suhoor": (.imsak, .sahur), "suhur": (.imsak, .sahur),
        "sehri": (.imsak, .sahur), "sahur": (.imsak, .sahur), "sunrise": (.sunrise, nil), "dhuhr": (.dhuhr, nil),
        "zuhr": (.dhuhr, nil), "asr": (.asr, nil), "maghrib": (.maghrib, nil), "iftar": (.maghrib, .iftar), "isha": (.isha, nil),
    ]

    public static func parse(_ command: String, language: AssistantLanguage, now: Date,
                             calendar: Calendar = .current) -> PrayerQuestion? {
        let words = TurkishText.folded(command).split(separator: " ").map(String.init)
        return language == .english
            ? english(words, command: command, now: now, calendar: calendar)
            : turkish(words, command: command, now: now, calendar: calendar)
    }

    private static func turkish(_ words: [String], command: String, now: Date, calendar: Calendar) -> PrayerQuestion? {
        guard words.contains(where: { word in turkishTopics.contains(where: word.hasPrefix) }),
              !words.contains(where: { word in turkishActionWords.contains(word) || turkishActions.contains(where: word.hasPrefix) })
        else { return nil }
        let match = turkishPrayers.first { entry in words.contains { $0.hasPrefix(entry.prefix) } }
        // "Ankara'da öğle ezanı" asks without a question word; "iftar menüsü öner" does not ask at all.
        let namesCall = match != nil && words.contains { $0.hasPrefix("ezan") || $0.hasPrefix("namaz") }
        guard namesCall || words.contains(where: { word in turkishAsks.contains(where: word.hasPrefix) }) else { return nil }
        let friday = zip(words, words.dropFirst()).contains { $0 == "cuma" && $1.hasPrefix("namaz") }
        if friday { return PrayerQuestion(prayer: .dhuhr, dayOffset: daysUntilFriday(now: now, calendar: calendar)) }
        let lists = words.contains { $0.hasPrefix("vakitler") || $0.hasPrefix("saatler") || $0 == "hepsi" || $0 == "tum" }
        return PrayerQuestion(prayer: match?.prayer, naming: match?.naming,
                              dayOffset: RelativeDayParser.dayOffset(in: command, now: now, calendar: calendar),
                              listsAll: match == nil && lists)
    }

    private static func english(_ words: [String], command: String, now: Date, calendar: Calendar) -> PrayerQuestion? {
        guard words.contains(where: englishTopics.contains), !words.contains(where: englishActions.contains),
              words.contains(where: englishAsks.contains) else { return nil }
        let friday = words.contains { $0 == "jummah" || $0 == "jumuah" }
            || zip(words, words.dropFirst()).contains { $0 == "friday" && $1.hasPrefix("prayer") }
        if friday { return PrayerQuestion(prayer: .dhuhr, dayOffset: daysUntilFriday(now: now, calendar: calendar)) }
        let match = words.lazy.compactMap { englishPrayers[$0] }.first
        let lists = words.contains { ["times", "schedule", "timetable"].contains($0) }
        return PrayerQuestion(prayer: match?.prayer, naming: match?.naming,
                              dayOffset: EnglishTimeParser.dayOffset(in: command, now: now, calendar: calendar),
                              listsAll: match == nil && lists)
    }

    /// "Cuma namazı kaçta" on a Friday is today's.
    private static func daysUntilFriday(now: Date, calendar: Calendar) -> Int {
        let friday = 6
        return (friday - calendar.component(.weekday, from: now) + 7) % 7
    }
}

/// The spoken answer to a `PrayerQuestion` from a list of days. Nil when the days asked about are not in
/// the list, so the caller can fetch a newer one.
public enum PrayerReport {
    private static let turkishWeekdays = ["pazar", "pazartesi", "salı", "çarşamba", "perşembe", "cuma", "cumartesi"]
    private static let englishWeekdays = ["Sunday", "Monday", "Tuesday", "Wednesday", "Thursday", "Friday", "Saturday"]

    public static func text(_ question: PrayerQuestion, days: [PrayerDay], city: String, now: Date,
                            language: AssistantLanguage) -> String? {
        guard let today = days.first(where: { $0.isDay(now) }) else { return nil }
        func day(_ offset: Int) -> PrayerDay? {
            guard let date = today.calendar.date(byAdding: .day, value: offset, to: now) else { return nil }
            return days.first { $0.isDay(date) }
        }
        let phrases = Phrases(city: city, language: language, now: now, timeZone: today.timeZone)
        let offset = question.dayOffset ?? 0
        guard let prayer = question.prayer else {
            if question.listsAll || offset > 0 {
                return day(offset).map { phrases.list($0, dayName: dayName(offset, of: $0, language: language)) }
            }
            if let next = Prayer.calls.first(where: { today.date(of: $0).map { $0 > now } ?? false }), let date = today.date(of: next) {
                return phrases.next(next, at: date, tomorrow: false)
            }
            return day(1).flatMap { tomorrow in tomorrow.date(of: .imsak).map { phrases.next(.imsak, at: $0, tomorrow: true) } }
        }
        let name = phrases.name(prayer, naming: question.naming)
        if offset > 0 {
            return day(offset).flatMap { other in
                other.date(of: prayer).map { phrases.onDay(name, at: $0, dayName: dayName(offset, of: other, language: language)) }
            }
        }
        guard let date = today.date(of: prayer) else { return nil }
        if date > now { return phrases.upcoming(name, at: date, tomorrow: false) }
        if question.dayOffset == 0 { return phrases.passed(name, at: date) }
        return day(1).flatMap { $0.date(of: prayer) }.map { phrases.upcoming(name, at: $0, tomorrow: true) }
    }

    private static func dayName(_ offset: Int, of day: PrayerDay, language: AssistantLanguage) -> String {
        let english = language == .english
        switch offset {
        case 0: return english ? "today" : "bugün"
        case 1: return english ? "tomorrow" : "yarın"
        default:
            guard let date = day.date(of: .dhuhr) else { return "" }
            let weekday = day.calendar.component(.weekday, from: date) - 1
            if offset < 7 { return english ? "on \(englishWeekdays[weekday])" : turkishWeekdays[weekday] }
            return english ? "on \(day.day).\(day.month)." : "\(day.day).\(day.month)."
        }
    }

    private struct Phrases {
        let city: String
        let language: AssistantLanguage
        let now: Date
        let timeZone: TimeZone

        private var english: Bool { language == .english }
        private var inCity: String { english ? "In \(city)," : TurkishGrammar.locative(city) }

        func name(_ prayer: Prayer, naming: PrayerQuestion.Naming?) -> String {
            if naming == .iftar { return "iftar" }
            if english { return englishName(prayer) }
            return switch prayer {
            case .imsak: "imsak"
            case .sunrise: "güneş doğuşu"
            case .dhuhr: "öğle ezanı"
            case .asr: "ikindi ezanı"
            case .maghrib: "akşam ezanı"
            case .isha: "yatsı ezanı"
            }
        }

        func upcoming(_ name: String, at date: Date, tomorrow: Bool) -> String {
            let remaining = SpokenDuration.text(minutes: minutes(until: date), language: language)
            if english { return "\(inCity) \(name) is \(tomorrow ? "tomorrow " : "")at \(clock(date)), in \(remaining)." }
            return "\(inCity) \(name) \(tomorrow ? "yarın " : "")\(locative(date)), \(remaining) kaldı."
        }

        func next(_ prayer: Prayer, at date: Date, tomorrow: Bool) -> String {
            let remaining = SpokenDuration.text(minutes: minutes(until: date), language: language)
            if english {
                return "\(inCity) the next prayer is \(englishName(prayer))\(tomorrow ? " tomorrow" : "") at \(clock(date)), in \(remaining)."
            }
            return "\(inCity) sıradaki vakit \(tomorrow ? "yarın " : "")\(shortTurkishName(prayer)), \(locative(date)); \(remaining) kaldı."
        }

        func passed(_ name: String, at date: Date) -> String {
            if english { return "\(inCity) \(name) was at \(clock(date)) today." }
            let time = locative(date)
            return "\(inCity) bugün \(name) \(time)\(time.hasSuffix("a") ? "ydı" : "ydi")."
        }

        func onDay(_ name: String, at date: Date, dayName: String) -> String {
            english ? "\(inCity) \(name) is at \(clock(date)) \(dayName)." : "\(inCity) \(dayName) \(name) \(locative(date))."
        }

        func list(_ day: PrayerDay, dayName: String) -> String {
            let items = Prayer.allCases.compactMap { prayer in
                day.date(of: prayer).map { "\(english ? englishName(prayer) : shortTurkishName(prayer)) \(clock($0))" }
            }.joined(separator: ", ")
            return english ? "Prayer times in \(city) \(dayName): \(items)." : "\(inCity) \(dayName) \(items)."
        }

        private func englishName(_ prayer: Prayer) -> String {
            switch prayer {
            case .imsak: "Fajr"
            case .sunrise: "sunrise"
            case .dhuhr: "Dhuhr"
            case .asr: "Asr"
            case .maghrib: "Maghrib"
            case .isha: "Isha"
            }
        }

        private func shortTurkishName(_ prayer: Prayer) -> String {
            switch prayer {
            case .imsak: "imsak"
            case .sunrise: "güneş"
            case .dhuhr: "öğle"
            case .asr: "ikindi"
            case .maghrib: "akşam"
            case .isha: "yatsı"
            }
        }

        private func minutes(until date: Date) -> Int {
            Int((date.timeIntervalSince(now) / 60).rounded(.up))
        }

        private func parts(_ date: Date) -> (hour: Int, minute: Int) {
            var calendar = Calendar(identifier: .gregorian)
            calendar.timeZone = timeZone
            let components = calendar.dateComponents([.hour, .minute], from: date)
            return (components.hour ?? 0, components.minute ?? 0)
        }

        private func clock(_ date: Date) -> String {
            let (hour, minute) = parts(date)
            return String(format: "%02d:%02d", hour, minute)
        }

        private func locative(_ date: Date) -> String {
            let (hour, minute) = parts(date)
            return TurkishGrammar.timeLocative(hour: hour, minute: minute)
        }
    }
}
