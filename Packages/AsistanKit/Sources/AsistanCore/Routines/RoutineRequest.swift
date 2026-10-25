import Foundation

/// Reads routine requests: "her gece 21'de hava durumunu söyle", "hafta içi her gün 7'de haberleri oku",
/// "every weekday at 7 read the news" (days, time and the command to run); "rutinlerim neler"; "akşam rutinini sil".
/// The schedule is the run of schedule words ending at the time ("hafta içi her gün 7'de"); everything else is the
/// command, run later exactly as if it had been said. A one-off ("cumartesi 10'da …") is not a routine.
public struct RoutineRequest: Equatable, Sendable {
    public let days: Set<Int>
    public let hour: Int
    public let minute: Int
    public let command: String

    public init(days: Set<Int>, hour: Int, minute: Int, command: String) {
        self.days = days
        self.hour = hour
        self.minute = minute
        self.command = command
    }

    public struct Removal: Equatable, Sendable {
        /// The words naming the routine ("aksam", "hava durumu"); empty when none were said.
        public let name: String
        public let every: Bool

        public init(name: String, every: Bool = false) {
            self.name = name
            self.every = every
        }
    }

    /// "cumartesi" before "cuma" and "pazartesi" before "pazar", which they start with.
    private static let turkishDays: [(stem: String, day: Int)] = [
        ("pazartesi", 0), ("sali", 1), ("carsamba", 2), ("persembe", 3), ("cumartesi", 5), ("cuma", 4), ("pazar", 6),
    ]
    private static let turkishDaySuffixLimit = 5
    private static let turkishSchedule: Set<String> = [
        "her", "gun", "gunu", "gunleri", "gunler", "sabah", "sabahlari", "aksam", "aksamlari", "gece", "geceleri",
        "ogle", "oglen", "ogleyin", "ogleden", "sonra", "hafta", "ici", "sonu", "sonlari", "ve", "saat",
    ]
    private static let turkishTime = try! NSRegularExpression(
        pattern: #"(?<![\p{L}\p{N}])(?:saat\s+)?(?:\d{1,2}:\d{2}(?:'\p{L}+)?|\d{1,2}(?:'[dt][ae]|\s+buçuk\p{L}*))(?![\p{L}\p{N}])"#
            + #"|(?<![\p{L}\p{N}])saat\s+\d{1,2}(?![\p{L}\p{N}:])"#,
        options: [.caseInsensitive])
    /// "21de" as a recognizer writes it, for "21'de".
    private static let bareSuffix = try! NSRegularExpression(pattern: #"(?<![\d:])(\d{1,2})([dt][ae])(?![\p{L}\p{N}])"#,
                                                             options: [.caseInsensitive])
    private static let clock = try! NSRegularExpression(pattern: #"(?<![\d:])(\d{1,2}):([0-5]\d)(?!\d)"#)
    private static let saidHour = try! NSRegularExpression(
        pattern: #"(?<![\p{L}\p{N}])saat\s+(\d{1,2})(?![\d:])(?:'\p{L}+)?(\s+buçuk)?"#
            + #"|(?<![\d:'])(\d{1,2})\s+buçuk(?!\p{L}*\s+(?:saat|dakika))"#
            + #"|(?<![\d:'])(\d{1,2})'[dt][ae](?![\p{L}\p{N}])"#,
        options: [.caseInsensitive])
    private static let lastAfternoonHour = 6

    private static let englishDays = ["monday", "tuesday", "wednesday", "thursday", "friday", "saturday", "sunday"]
    private static let englishSchedule: Set<String> = Set(englishDays + englishDays.map { $0 + "s" }).union([
        "every", "each", "day", "daily", "morning", "mornings", "evening", "evenings", "night", "nights", "afternoon",
        "afternoons", "weekday", "weekdays", "weekend", "weekends", "on", "and", "the",
    ])
    private static let englishTime = try! NSRegularExpression(
        pattern: #"\b(?:at\s+)?(?:\d{1,2}:\d{2}(?:\s*[ap]\.?\s*m\b\.?)?|\d{1,2}\s*[ap]\.?\s*m\b\.?|noon|midnight)"#
            + partOfDayPattern
            + #"|\bat\s+(?:\d{1,2}|one|two|three|four|five|six|seven|eight|nine|ten|eleven|twelve)\b(?:\s+o'?clock)?"#
            + partOfDayPattern,
        options: [.caseInsensitive])
    private static var partOfDayPattern: String { #"(?:\s+in\s+the\s+(?:morning|afternoon|evening)|\s+at\s+night)?"# }
    private static let repeatingEnglishParts: Set<String> = Set(englishDays + ["morning", "evening", "night", "afternoon"])

    private static let turkishRemoveVerbs = ["sil", "kaldir", "iptal", "kapat"]
    private static let englishRemoveVerbs: Set<String> = ["delete", "remove", "cancel", "clear", "stop"]
    private static let allWords: Set<String> = ["butun", "tum", "hepsini", "hepsi", "all", "every"]
    private static let nameFiller: Set<String> = ["bu", "su", "o", "benim", "the", "my", "a", "that", "this"]
    private static let turkishListWords: Set<String> = [
        "neler", "ne", "nedir", "hangi", "hangileri", "listele", "say", "oku", "var", "goster", "soyle",
    ]
    private static let englishListWords: Set<String> = ["what", "which", "list", "read", "tell", "show", "any", "have"]

    /// nil unless the text says a repeating schedule, a time and something to do. A request that talks about the
    /// routine itself ("… bir rutin oluştur") is left alone.
    public static func parse(_ text: String, language: AssistantLanguage) -> RoutineRequest? {
        guard !mentionsRoutine(text) else { return nil }
        return language == .english ? parseEnglish(text) : parseTurkish(text)
    }

    public static func asksForList(_ text: String, language: AssistantLanguage) -> Bool {
        let words = folded(text)
        guard words.contains(where: isRoutineWord), removal(text, language: language) == nil else { return false }
        let listWords = language == .english ? englishListWords : turkishListWords
        return words.count == 1 || words.contains(where: listWords.contains)
    }

    public static func removal(_ text: String, language: AssistantLanguage) -> Removal? {
        let words = folded(text)
        guard let at = words.firstIndex(where: isRoutineWord) else { return nil }
        let named: ArraySlice<String>
        if language == .english {
            guard let verb = words.firstIndex(where: englishRemoveVerbs.contains) else { return nil }
            named = verb < at ? words[(verb + 1)..<at] : words[..<at]
        } else {
            guard words[(at + 1)...].contains(where: { word in turkishRemoveVerbs.contains(where: word.hasPrefix) }) else { return nil }
            named = words[..<at]
        }
        let everyRoutine = language == .turkish && named.isEmpty
            && (words[at].hasPrefix("rutinleri") || words[at].hasPrefix("rutinlerin"))
        if named.contains(where: allWords.contains) || everyRoutine { return Removal(name: "", every: true) }
        return Removal(name: named.filter { !nameFiller.contains($0) }.joined(separator: " "))
    }

    private static func mentionsRoutine(_ text: String) -> Bool {
        folded(text).contains(where: isRoutineWord)
    }

    private static func isRoutineWord(_ word: String) -> Bool {
        word.hasPrefix("rutin") || word.hasPrefix("routine")
    }

    private static func folded(_ text: String) -> [String] {
        TurkishText.folded(text).split(separator: " ").map(String.init)
    }

    // MARK: - Turkish

    private static func parseTurkish(_ text: String) -> RoutineRequest? {
        let straightened = text.replacingOccurrences(of: "’", with: "'")
        let digitized = withApostrophes(TurkishNumberParser.digitize(withApostrophes(straightened)))
        let resolved = TurkishTimeOfDay.resolve(digitized)
        guard let (time, timeRange) = firstMatch(of: turkishTime, in: resolved) else { return nil }
        let before = words(resolved[..<timeRange.lowerBound])
        let taken = scheduleTail(before) { turkishSchedule.contains(TurkishText.folded($0)) || turkishDay($0) != nil }
        let scheduleWords = Array(before.suffix(taken))
        guard let days = turkishDays(scheduleWords.map(TurkishText.folded)),
              let (hour, minute) = turkishClock((scheduleWords + [time]).joined(separator: " "))
        else { return nil }
        return request(days: days, hour: hour, minute: minute,
                       rest: Array(before.dropLast(taken)) + words(resolved[timeRange.upperBound...]), edges: ["ve"])
    }

    private static func withApostrophes(_ text: String) -> String {
        let range = NSRange(text.startIndex..., in: text)
        return bareSuffix.stringByReplacingMatches(in: text, range: range, withTemplate: "$1'$2")
    }

    private static func turkishDay(_ word: String) -> Int? {
        let plain = TurkishText.folded(word)
        return turkishDays.first { plain.hasPrefix($0.stem) && plain.count - $0.stem.count <= turkishDaySuffixLimit }?.day
    }

    private static func turkishDays(_ schedule: [String]) -> Set<Int>? {
        let named = Set(schedule.compactMap(turkishDay))
        let repeating = schedule.contains("her") || schedule.contains { $0.hasSuffix("leri") || $0.hasSuffix("lari") }
        if !named.isEmpty { return repeating ? named : nil }
        if schedule.contains("hafta"), schedule.contains("ici") { return RoutineSchedule.weekdays }
        if schedule.contains("hafta"), schedule.contains("sonu") || schedule.contains("sonlari") { return RoutineSchedule.weekend }
        return repeating ? RoutineSchedule.everyDay : nil
    }

    /// (hour, minute) on a 24-hour clock. `TurkishTimeOfDay` writes "08:00" for "sabah 8"; a bare "7'de" or a
    /// recognizer's own "7:00" follows the words around it, and a bare 1 to 6 means the afternoon.
    private static func turkishClock(_ text: String) -> (Int, Int)? {
        let folded = TurkishText.folded(text)
        if let match = groups(of: clock, in: text), let hour = match[1].flatMap(Int.init), let minute = match[2].flatMap(Int.init) {
            let isBare = match[1]?.count == 1
            return (isBare ? afternoon(hour, folded: folded) : hour, minute)
        }
        guard let match = groups(of: saidHour, in: text),
              let hour = (match[1] ?? match[3] ?? match[4]).flatMap(Int.init), hour < 24 else { return nil }
        let half = match[2] != nil || match[3] != nil
        return (afternoon(hour, folded: folded), half ? 30 : 0)
    }

    private static func afternoon(_ hour: Int, folded: String) -> Int {
        let words = Set(folded.split(separator: " ").map(String.init))
        if words.contains("sabah") || hour >= 12 { return hour }
        if words.contains("aksam") || (words.contains("ogleden") && words.contains("sonra")) { return hour + 12 }
        if words.contains("gece") { return hour > lastAfternoonHour ? hour + 12 : hour }
        return (1...lastAfternoonHour).contains(hour) ? hour + 12 : hour
    }

    // MARK: - English

    private static func parseEnglish(_ text: String) -> RoutineRequest? {
        guard let (time, timeRange) = firstMatch(of: englishTime, in: text) else { return nil }
        let before = words(text[..<timeRange.lowerBound])
        let after = words(text[timeRange.upperBound...])
        let isSchedule = { (word: String) in englishSchedule.contains(englishWord(word)) }
        let taken = scheduleTail(before, isSchedule: isSchedule)
        // "at 7 every weekday, read the news": the schedule may also follow the time.
        var following = 0
        if let first = after.first, ["every", "each", "on", "daily"].contains(englishWord(first)) {
            following = after.prefix(while: isSchedule).count
        }
        let scheduleWords = Array(before.suffix(taken)) + after.prefix(following)
        guard let days = englishDays(scheduleWords.map(englishWord)),
              let parsed = EnglishTimeParser.parse((scheduleWords + [time]).joined(separator: " "), appointment: false),
              let hour = parsed.hour
        else { return nil }
        return request(days: days, hour: hour, minute: parsed.minute ?? 0,
                       rest: Array(before.dropLast(taken)) + after.dropFirst(following), edges: ["and", "please", "then"])
    }

    private static func englishWord(_ word: String) -> String {
        word.trimmingCharacters(in: CharacterSet(charactersIn: ",.;:!?")).lowercased()
    }

    private static func englishDays(_ schedule: [String]) -> Set<Int>? {
        let named = Set(englishDays.indices.filter { index in
            schedule.contains(englishDays[index]) || schedule.contains(englishDays[index] + "s")
        })
        let repeating = !Set(schedule).isDisjoint(with: ["every", "each", "daily"])
            || schedule.contains { $0.hasSuffix("s") && repeatingEnglishParts.contains(String($0.dropLast())) }
        if !named.isEmpty { return repeating ? named : nil }
        if !Set(schedule).isDisjoint(with: ["weekday", "weekdays"]) { return RoutineSchedule.weekdays }
        if !Set(schedule).isDisjoint(with: ["weekend", "weekends"]) { return RoutineSchedule.weekend }
        return repeating ? RoutineSchedule.everyDay : nil
    }

    // MARK: - Shared

    private static func scheduleTail(_ words: [String], isSchedule: (String) -> Bool) -> Int {
        words.reversed().prefix(while: isSchedule).count
    }

    private static func request(days: Set<Int>, hour: Int, minute: Int, rest: [String], edges: Set<String>) -> RoutineRequest? {
        let punctuation = CharacterSet(charactersIn: " ,.;:")
        var words = words(rest.joined(separator: " ").trimmingCharacters(in: punctuation))
        let isEdge = { (word: String) in edges.contains(TurkishText.folded(word)) }
        while let first = words.first, isEdge(first) { words.removeFirst() }
        while let last = words.last, isEdge(last) { words.removeLast() }
        let command = words.joined(separator: " ").trimmingCharacters(in: punctuation)
        guard !command.isEmpty, command.count <= Routine.maxCommandCharacters else { return nil }
        return RoutineRequest(days: days, hour: hour, minute: minute, command: command)
    }

    private static func words(_ text: Substring) -> [String] {
        text.split(whereSeparator: \.isWhitespace).map(String.init)
    }

    private static func words(_ text: String) -> [String] {
        words(text[...])
    }

    private static func firstMatch(of pattern: NSRegularExpression, in text: String) -> (String, Range<String.Index>)? {
        guard let match = pattern.firstMatch(in: text, range: NSRange(text.startIndex..., in: text)),
              let range = Range(match.range, in: text) else { return nil }
        return (String(text[range]), range)
    }

    /// Every capture group of the first match, nil where a group took no part.
    private static func groups(of pattern: NSRegularExpression, in text: String) -> [String?]? {
        guard let match = pattern.firstMatch(in: text, range: NSRange(text.startIndex..., in: text)) else { return nil }
        return (0..<match.numberOfRanges).map { index in
            Range(match.range(at: index), in: text).map { String(text[$0]) }
        }
    }
}
