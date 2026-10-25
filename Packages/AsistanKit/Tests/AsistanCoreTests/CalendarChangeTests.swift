import Foundation
import Testing
@testable import AsistanCore

@Suite("Calendar changes")
struct CalendarChangeTests {
    typealias Target = CalendarChange.Target

    var calendar: Calendar {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "Europe/Istanbul")!
        calendar.firstWeekday = 2
        return calendar
    }

    /// Tuesday, 13 Oct 2026, 09:00
    var now: Date { date(day: 13, hour: 9) }

    func date(day: Int, hour: Int, minute: Int = 0) -> Date {
        calendar.date(from: DateComponents(year: 2026, month: 10, day: day, hour: hour, minute: minute))!
    }

    func parse(_ text: String, language: AssistantLanguage = .turkish) -> CalendarChange? {
        let resolved = language == .turkish ? TurkishTimeOfDay.resolve(TurkishNumberParser.digitize(text)) : text
        return CalendarChange.parse(resolved, language: language, now: now, calendar: calendar)
    }

    func target(_ text: String, language: AssistantLanguage = .turkish) -> Target? {
        guard case let .move(target)? = parse(text, language: language)?.action else { return nil }
        return target
    }

    @Test("cancelling names the event by its kind and day")
    func cancel() throws {
        let change = try #require(parse("yarınki toplantıyı iptal et"))
        #expect(change.action == .cancel)
        #expect(change.event == CalendarChange.Event(kindWords: ["toplantıyı"], period: .day(offset: 1)))
        #expect(change.isClearlyAboutCalendar)
        #expect(parse("Diş hekimi randevumu sil")?.event.titleWords == ["Diş", "hekimi"])
        #expect(parse("haftalık toplantının hepsini iptal et")?.allOccurrences == true)
        #expect(parse("yarınki toplantıyı iptal et")?.allOccurrences == false)
    }

    @Test("moving reads the event before the object and where it goes after it")
    func move() throws {
        let dentist = try #require(parse("diş hekimi randevusunu cumaya al"))
        #expect(dentist.event.titleWords == ["diş", "hekimi"])
        #expect(dentist.action == .move(Target(dayOffset: 3)))
        let meeting = try #require(parse("saat 3'teki toplantıyı 4'e ertele"))
        #expect(meeting.event.hour == 15)
        #expect(meeting.action == .move(Target(hour: 16, minute: 0)))
    }

    @Test("targets: a day, a time, a shift", arguments: [
        ("toplantıyı yarım saat öne al", Target(shiftMinutes: -30)),
        ("toplantıyı 1 saat ertele", Target(shiftMinutes: 60)),
        ("toplantıyı haftaya ertele", Target(shiftDays: 7)),
        ("toplantıyı ertesi güne al", Target(shiftDays: 1)),
        ("akşam 5'teki randevumu yarın sabah 10'a al", Target(dayOffset: 1, hour: 10, minute: 0)),
        ("sabah 9 buçuktaki görüşmeyi 11'e al", Target(hour: 11, minute: 0)),
        ("dişçi randevumu cuma 4 buçuğa al", Target(dayOffset: 3, hour: 16, minute: 30)),
        ("toplantıyı öğleye al", Target(hour: 12, minute: 0)),
    ])
    func targets(command: String, expected: Target) {
        #expect(target(command) == expected)
    }

    @Test("the event's own time is read too")
    func eventTimes() {
        #expect(parse("akşam 5'teki randevumu yarın sabah 10'a al")?.event.hour == 17)
        let morning = parse("sabah 9 buçuktaki görüşmeyi 11'e al")?.event
        #expect(morning?.hour == 9 && morning?.minute == 30)
        #expect(parse("toplantıyı ertele").map { $0.action == .move(Target()) } == true)
    }

    @Test("not about the calendar", arguments: [
        "alarmı iptal et", "süt al", "zamanlayıcıyı sil", "siparişimi iptal et", "dosyayı çöp kutusuna taşı",
        "fotoğrafı masaüstüne taşı", "yarın ekmek al", "müziği durdur", "hepsini iptal et", "alışveriş notunu sil",
    ])
    func notCalendar(command: String) {
        #expect(parse(command) == nil)
    }

    @Test("English requests")
    func english() throws {
        let cancel = try #require(parse("cancel tomorrow's meeting", language: .english))
        #expect(cancel.action == .cancel)
        #expect(cancel.event == CalendarChange.Event(kindWords: ["meeting"], period: .day(offset: 1)))
        let dentist = try #require(parse("move the dentist appointment to Friday", language: .english))
        #expect(dentist.event.titleWords == ["dentist"])
        #expect(dentist.action == .move(Target(dayOffset: 3)))
        let threeOClock = try #require(parse("move the 3 o'clock meeting to 4", language: .english))
        #expect(threeOClock.event.hour == 15)
        #expect(threeOClock.action == .move(Target(hour: 16, minute: 0)))
        #expect(target("push the standup back half an hour", language: .english) == Target(shiftMinutes: 30))
        #expect(target("move the review an hour later", language: .english) == Target(shiftMinutes: 60))
        #expect(parse("reschedule all the weekly review meetings to Monday", language: .english)?.allOccurrences == true)
        for command in ["cancel the timer", "delete this file", "move the window to the left", "what's on my calendar"] {
            #expect(parse(command, language: .english) == nil)
        }
    }

    var candidates: [CalendarEventCandidate] {
        [
            .init(id: "a", title: "Ekip toplantısı", start: date(day: 14, hour: 10), end: date(day: 14, hour: 11),
                  isAllDay: false, isRecurring: false),
            .init(id: "b", title: "Diş hekimi", start: date(day: 16, hour: 15), end: date(day: 16, hour: 15, minute: 30),
                  isAllDay: false, isRecurring: false),
            .init(id: "c", title: "Proje toplantısı", start: date(day: 13, hour: 15), end: date(day: 13, hour: 16),
                  isAllDay: false, isRecurring: false),
            .init(id: "d", title: "Standup", start: date(day: 14, hour: 9, minute: 30), end: date(day: 14, hour: 9, minute: 45),
                  isAllDay: false, isRecurring: true),
            .init(id: "d", title: "Standup", start: date(day: 15, hour: 9, minute: 30), end: date(day: 15, hour: 9, minute: 45),
                  isAllDay: false, isRecurring: true),
            .init(id: "e", title: "Doğum günü", start: date(day: 17, hour: 0), end: date(day: 18, hour: 0),
                  isAllDay: true, isRecurring: false),
        ]
    }

    func matches(_ command: String, language: AssistantLanguage = .turkish) -> [CalendarEventCandidate] {
        guard let change = parse(command, language: language) else { return [] }
        return change.matches(in: candidates, now: now, calendar: calendar)
    }

    @Test("finds the event meant", arguments: [
        ("yarınki toplantıyı iptal et", ["a"]),
        ("diş hekimi randevusunu cumaya al", ["b"]),
        ("saat 3'teki toplantıyı 4'e ertele", ["c"]),
        ("standup toplantısını iptal et", ["d"]),
        ("yarınki randevumu iptal et", ["d", "a"]),
        ("toplantıyı iptal et", ["c", "a"]),
        ("pazartesiki toplantıyı iptal et", []),
    ])
    func finds(command: String, ids: [String]) {
        #expect(matches(command).map(\.id) == ids)
    }

    @Test("occurrences of one event mean the next of them")
    func nextOccurrence() {
        #expect(matches("standup toplantısını iptal et").first?.start == date(day: 14, hour: 9, minute: 30))
        #expect(matches("cancel the standup", language: .english).map(\.id) == ["d"])
    }

    @Test("a moved event keeps what is not said")
    func newStart() throws {
        func moved(_ command: String, _ id: String) throws -> Date? {
            let change = try #require(parse(command))
            let candidate = try #require(candidates.first { $0.id == id })
            return change.newStart(for: candidate, now: now, calendar: calendar)
        }
        #expect(try moved("diş hekimi randevusunu pazartesiye al", "b") == date(day: 19, hour: 15))
        #expect(try moved("saat 3'teki toplantıyı 4'e ertele", "c") == date(day: 13, hour: 16))
        #expect(try moved("toplantıyı yarım saat öne al", "a") == date(day: 14, hour: 9, minute: 30))
        #expect(try moved("toplantıyı haftaya ertele", "a") == date(day: 21, hour: 10))
        #expect(try moved("doğum gününü cumartesiye al", "e") == date(day: 17, hour: 0))
        #expect(try moved("doğum gününü 4'e al", "e") == nil)
        #expect(try moved("toplantıyı ertele", "a") == nil)
    }
}
