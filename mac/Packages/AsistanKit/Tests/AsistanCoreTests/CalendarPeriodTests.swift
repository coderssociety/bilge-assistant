import Foundation
import Testing
@testable import AsistanCore

@Suite("CalendarPeriod")
struct CalendarPeriodTests {
    var calendar: Calendar {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "Europe/Istanbul")!
        calendar.firstWeekday = 2
        return calendar
    }

    /// Tuesday, 13 Oct 2026
    var tuesday: Date { calendar.date(from: DateComponents(year: 2026, month: 10, day: 13, hour: 9))! }

    func date(_ day: Int, month: Int = 10) -> Date {
        calendar.date(from: DateComponents(year: 2026, month: month, day: day))!
    }

    @Test("reads the day or span a calendar question asks about", arguments: [
        ("bugün ne var", CalendarPeriod.day(offset: 0)),
        ("yarın toplantım var mı", .day(offset: 1)),
        ("cuma günü toplantım var mı", .day(offset: 3)),
        ("haftaya pazartesi ne var", .day(offset: 6)),
        ("önümüzdeki hafta neler var", .nextWeek),
        ("haftaya ne var", .nextWeek),
        ("bu hafta takvimde ne var", .thisWeek),
        ("bu ay kaç toplantım var", .thisMonth),
        ("15 Kasım'da ne var", .day(offset: 33)),
    ])
    func turkish(text: String, expected: CalendarPeriod) {
        #expect(CalendarPeriod.parse(text, language: .turkish, now: tuesday, calendar: calendar) == expected)
    }

    @Test("reads English calendar questions", arguments: [
        ("what's on my calendar next week", CalendarPeriod.nextWeek),
        ("anything this month", .thisMonth),
        ("do I have meetings on Friday", .day(offset: 3)),
        ("what do I have this week", .thisWeek),
    ])
    func english(text: String, expected: CalendarPeriod) {
        #expect(CalendarPeriod.parse(text, language: .english, now: tuesday, calendar: calendar) == expected)
    }

    @Test("returns nil when the question names no time")
    func none() {
        #expect(CalendarPeriod.parse("takvimimde ne var", language: .turkish, now: tuesday, calendar: calendar) == nil)
    }

    @Test("turns a period into the dates to read")
    func intervals() {
        #expect(CalendarPeriod.day(offset: 3).interval(now: tuesday, calendar: calendar) == DateInterval(start: date(16), end: date(17)))
        #expect(CalendarPeriod.thisWeek.interval(now: tuesday, calendar: calendar) == DateInterval(start: date(13), end: date(20)))
        #expect(CalendarPeriod.nextWeek.interval(now: tuesday, calendar: calendar) == DateInterval(start: date(19), end: date(26)))
        #expect(CalendarPeriod.thisMonth.interval(now: tuesday, calendar: calendar) == DateInterval(start: date(13), end: date(1, month: 11)))
    }
}
