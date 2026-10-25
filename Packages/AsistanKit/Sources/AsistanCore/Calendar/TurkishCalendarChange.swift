import Foundation

/// Reads a Turkish cancel or move request (after number digitizing and time-of-day resolving). Turkish puts
/// the verb last and the event before it as the object ("toplantıyı"); a move names where it goes in the
/// dative after the object ("cumaya", "4'e", "saat 17:00'ye").
enum TurkishCalendarChange {
    private static let etVerbs: Set<String> = ["et", "eder", "etsene", "edebilir", "edin", "ediver"]
    private static let deleteVerbs: Set<String> = ["sil", "siler", "silsene", "silebilir", "silin", "siliver"]
    private static let takeVerbs: Set<String> = ["al", "alir", "alsana", "alabilir", "alin", "aliver"]
    private static let pullVerbs: Set<String> = ["cek", "ceker", "ceksene", "cekebilir", "cekin"]
    private static let allWords: Set<String> = ["hepsini", "tumunu", "butun", "tamamini", "serisini", "her", "tum"]
    private static let kindStems = ["toplanti", "randevu", "etkinlig", "etkinlik", "gorusme", "bulusma", "mulakat", "seans"]
    private static let notEvents = [
        "alarm", "zamanlayici", "sayac", "animsatici", "hatirlat", "dosya", "klasor", "mail", "eposta", "mesaj", "sarki",
        "muzik", "siparis", "abonelik", "uyelik", "pencere", "sekme", "indirme", "guncelleme", "yapilacak", "gorev",
    ]
    private static let noteWords: Set<String> = ["not", "notu", "notumu", "notunu", "notlari", "notlarimi"]
    private static let fillers: Set<String> = [
        "saat", "bir", "benim", "bu", "su", "o", "olan", "ilk", "sonraki", "gelecek", "onumuzdeki", "hafta", "haftaki",
        "haftanin", "gun", "gunku", "gunki", "obur", "ertesi", "lutfen", "bilge", "sabah", "aksam", "gece", "ogleden",
        "sonra", "sabahki", "aksamki", "geceki", "oglenki", "oglen", "bucuk", "bucuktaki", "bucukta",
    ]
    /// Words after the object that end like an accusative but are not one.
    private static let notObjects: Set<String> = ["ileri", "geri", "sonrasi", "ertesi"]
    private static let earlierWords: Set<String> = ["one", "once", "erkene", "geri"]
    private static let months = ["ocak", "subat", "mart", "nisan", "mayis", "haziran", "temmuz", "agustos", "eylul", "ekim",
                                 "kasim", "aralik"]
    private static let durationWords = ["saat", "dakika", "saniye", "gun", "hafta"]

    static func parse(_ command: String, now: Date, calendar: Calendar) -> CalendarChange? {
        let words = SpokenWords(clockJoined(command))
        let folded = words.folded
        let end = words.contentEnd
        guard end >= 2 else { return nil }
        let verb = folded[end - 1]
        var body = Array(0..<end - 1)
        let isMove: Bool
        var needsTarget = false
        if verb == "iptal" || deleteVerbs.contains(verb) || verb.hasPrefix("kaldir") {
            isMove = false
        } else if etVerbs.contains(verb), end >= 3, folded[end - 2] == "iptal" {
            isMove = false
            body.removeLast()
        } else if verb.hasPrefix("ertele") {
            isMove = true
        } else if takeVerbs.contains(verb) || pullVerbs.contains(verb) || verb.hasPrefix("tasi") || verb.hasPrefix("kaydir") {
            (isMove, needsTarget) = (true, true)
        } else {
            return nil
        }
        let allOccurrences = body.contains { allWords.contains(folded[$0]) }
        body.removeAll { allWords.contains(folded[$0]) }
        var eventPart = body
        var targetPart: [Int] = []
        if isMove, let object = body.last(where: { isObject(folded[$0]) }) {
            eventPart = body.filter { $0 <= object }
            targetPart = body.filter { $0 > object }
        }
        guard !eventPart.isEmpty, !eventPart.contains(where: { isNotEvent(folded[$0]) }) else { return nil }
        let event = describeEvent(eventPart, in: words, now: now, calendar: calendar)
        guard isMove else { return CalendarChange(action: .cancel, event: event, allOccurrences: allOccurrences) }
        let target = describeTarget(targetPart, in: words, now: now, calendar: calendar)
        if needsTarget, target.isEmpty { return nil }
        return CalendarChange(action: .move(target), event: event, allOccurrences: allOccurrences)
    }

    /// "17:00'ye" folds to "17 00ye"; joining the clock keeps it one word, "17h00ye".
    private static func clockJoined(_ command: String) -> String {
        command.replacingOccurrences(of: #"(?<!\d)(\d{1,2})[:.](\d{2})(?!\d)"#, with: "$1h$2", options: .regularExpression)
    }

    private static func isObject(_ word: String) -> Bool {
        guard let first = word.first, !first.isNumber, !notObjects.contains(word), !word.hasSuffix("ki"), !word.hasSuffix("ku")
        else { return false }
        return word.hasSuffix("i") || word.hasSuffix("u")
    }

    private static func isNotEvent(_ word: String) -> Bool {
        noteWords.contains(word) || notEvents.contains(where: word.hasPrefix)
    }

    private static func describeEvent(_ part: [Int], in words: SpokenWords, now: Date, calendar: Calendar) -> CalendarChange.Event {
        let folded = part.map { words.folded[$0] }
        let text = folded.joined(separator: " ").replacingOccurrences(of: "haftaki", with: "hafta")
        let time = clockTime(folded, endings: ["deki", "daki", "teki", "taki", "de", "da", "te", "ta", "ki", ""],
                             noonWords: ["oglen", "oglenki", "ogleyin"])
        var dayWords = Set<Int>()
        for (offset, word) in folded.enumerated() {
            let next = offset + 1 < folded.count ? folded[offset + 1] : ""
            if RelativeDayParser.dayOffset(in: word, now: now, calendar: calendar) != nil
                || (word.first?.isNumber == true && months.contains(where: next.hasPrefix))
                || months.contains(where: word.hasPrefix) {
                dayWords.insert(offset)
            }
        }
        var titleWords: [String] = []
        var kindWords: [String] = []
        for (offset, index) in part.enumerated() {
            let word = folded[offset]
            guard !dayWords.contains(offset), !fillers.contains(word), !word.hasPrefix("takvim"), word.first?.isNumber != true,
                  !word.isEmpty else { continue }
            let said = words.text(index..<index + 1)
            if kindStems.contains(where: word.hasPrefix) { kindWords.append(said) } else { titleWords.append(said) }
        }
        return CalendarChange.Event(titleWords: titleWords, kindWords: kindWords,
                                    period: CalendarPeriod.parse(text, language: .turkish, now: now, calendar: calendar),
                                    hour: time?.hour, minute: time?.minute)
    }

    private static func describeTarget(_ part: [Int], in words: SpokenWords, now: Date, calendar: Calendar) -> CalendarChange.Target {
        let folded = part.map { words.folded[$0] }
        let text = folded.joined(separator: " ")
        let raw = part.map { words.raw[$0] }.joined(separator: " ")
        var target = CalendarChange.Target()
        let earlier = folded.contains(where: earlierWords.contains)
        if let seconds = TimerPhraseParser.parse(raw)?.durationSeconds, folded.contains(where: { $0 == "saat" || $0 == "dakika" }),
           !folded.contains(where: { $0.hasPrefix("gun") || $0.hasPrefix("hafta") }) {
            target.shiftMinutes = (earlier ? -1 : 1) * seconds / 60
            return target
        }
        target.shiftDays = dayShift(text)
        if target.shiftDays == nil { target.dayOffset = RelativeDayParser.dayOffset(in: text, now: now, calendar: calendar) }
        if let time = clockTime(folded, endings: ["e", "a", "ye", "ya", ""], noonWords: ["ogleye", "oglene", "oglen"]) {
            (target.hour, target.minute) = (time.hour, time.minute)
        }
        return target
    }

    /// "Haftaya ertele" is a week after the event, not a week from today; so are "ertesi güne" and "2 gün sonraya".
    private static func dayShift(_ text: String) -> Int? {
        if !RelativeDayParser.namesWeekday(text), text.contains("haftaya") || text.contains("hafta sonraya") {
            return 7 * (leadingNumber(before: " hafta", in: text) ?? 1)
        }
        if text.contains("ertesi gun") { return 1 }
        return text.contains("gun sonraya") || text.contains("gun ileri") ? leadingNumber(before: " gun", in: text) : nil
    }

    private static func leadingNumber(before word: String, in text: String) -> Int? {
        guard let range = text.range(of: #"(\d+)"# + word, options: .regularExpression) else { return nil }
        return Int(text[range].prefix { $0.isNumber })
    }

    /// "3'teki", "saat 10'daki", "17h00ye", "4 buçuğa", "öğlen". A bare number counts only after "saat";
    /// a day of the month ("15 kasım") or a duration ("2 saat") is not a time.
    private static func clockTime(_ folded: [String], endings: Set<String>, noonWords: Set<String>) -> (hour: Int, minute: Int)? {
        let text = folded.joined(separator: " ")
        for (index, word) in folded.enumerated() {
            if noonWords.contains(word) { return (12, 0) }
            guard let match = word.firstMatch(of: /^(\d{1,2})(?:h(\d{2}))?(\p{L}*)$/), let hour = Int(match.1), hour < 24,
                  endings.contains(String(match.3))
            else { continue }
            let next = index + 1 < folded.count ? folded[index + 1] : ""
            if durationWords.contains(where: next.hasPrefix) || months.contains(where: next.hasPrefix) { continue }
            let half = next.hasPrefix("bucu")
            if match.3.isEmpty, match.2 == nil, !half, !(index > 0 && folded[index - 1] == "saat") { continue }
            let minute = match.2.flatMap { Int($0) } ?? (half ? 30 : 0)
            let saidOnTwelveHourClock = match.2 == nil || match.1.count == 1
            return (saidOnTwelveHourClock ? TimerPhraseParser.appointmentHour(hour, in: text) : hour, minute)
        }
        return nil
    }
}
