import Foundation
import Testing
@testable import AsistanCore

@Suite("RoutineSchedule")
struct RoutineScheduleTests {
    var calendar: Calendar {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "Europe/Istanbul")!
        return calendar
    }

    /// Sunday 25 October 2026 in Istanbul.
    func date(day: Int = 25, hour: Int, minute: Int = 0, second: Int = 0) -> Date {
        calendar.date(from: DateComponents(year: 2026, month: 10, day: day, hour: hour, minute: minute, second: second))!
    }

    func routine(_ days: Set<Int>, _ hour: Int, _ minute: Int = 0, _ command: String = "hava durumunu söyle") -> Routine {
        Routine(days: days, hour: hour, minute: minute, command: command)!
    }

    @Test("weekdays count from Monday")
    func weekday() {
        #expect(RoutineSchedule.weekday(of: date(hour: 12), calendar: calendar) == 6)
        #expect(RoutineSchedule.weekday(of: date(day: 26, hour: 12), calendar: calendar) == 0)
    }

    @Test("a routine is due once when its minute is passed")
    func dueOnce() {
        let evening = routine(RoutineSchedule.everyDay, 21)
        let first = RoutineSchedule.due([evening], after: date(hour: 20, minute: 59, second: 50), upTo: date(hour: 21, second: 5),
                                        grace: 600, calendar: calendar)
        #expect(first == [evening])
        let second = RoutineSchedule.due([evening], after: date(hour: 21, second: 5), upTo: date(hour: 21, second: 20),
                                         grace: 600, calendar: calendar)
        #expect(second.isEmpty)
    }

    @Test("only on its days")
    func onItsDays() {
        let weekdays = routine(RoutineSchedule.weekdays, 7)
        // Sunday morning
        #expect(RoutineSchedule.due([weekdays], after: date(hour: 6, minute: 59), upTo: date(hour: 7, minute: 1),
                                    grace: 600, calendar: calendar).isEmpty)
        // Monday morning
        #expect(RoutineSchedule.due([weekdays], after: date(day: 26, hour: 6, minute: 59), upTo: date(day: 26, hour: 7, minute: 1),
                                    grace: 600, calendar: calendar) == [weekdays])
    }

    @Test("a time missed by more than the grace, while asleep or closed, is skipped")
    func missedIsSkipped() {
        let morning = routine(RoutineSchedule.everyDay, 8)
        #expect(RoutineSchedule.due([morning], after: date(hour: 7), upTo: date(hour: 9), grace: 600, calendar: calendar).isEmpty)
        #expect(RoutineSchedule.due([morning], after: date(hour: 7), upTo: date(hour: 8, minute: 5), grace: 600, calendar: calendar) == [morning])
    }

    @Test("the next time it comes due")
    func next() {
        let saturday = routine([5], 10)
        #expect(RoutineSchedule.nextOccurrence(of: saturday, after: date(hour: 12), calendar: calendar) == date(day: 31, hour: 10))
        let daily = routine(RoutineSchedule.everyDay, 21, 30)
        #expect(RoutineSchedule.nextOccurrence(of: daily, after: date(hour: 12), calendar: calendar) == date(hour: 21, minute: 30))
        #expect(RoutineSchedule.nextOccurrence(of: daily, after: date(hour: 21, minute: 30), calendar: calendar) == date(day: 26, hour: 21, minute: 30))
    }

    @Test("schedules are said back in each language")
    func describe() {
        #expect(RoutineSchedule.describe(days: RoutineSchedule.everyDay, hour: 21, minute: 0, language: .turkish) == "her gün 21:00'de")
        #expect(RoutineSchedule.describe(days: RoutineSchedule.weekdays, hour: 7, minute: 0, language: .turkish) == "hafta içi her gün 07:00'de")
        #expect(RoutineSchedule.describe(days: RoutineSchedule.weekend, hour: 10, minute: 0, language: .turkish) == "hafta sonları 10:00'da")
        #expect(RoutineSchedule.describe(days: [0], hour: 9, minute: 0, language: .turkish) == "her pazartesi 09:00'da")
        #expect(RoutineSchedule.describe(days: [0, 2, 4], hour: 8, minute: 30, language: .turkish)
            == "pazartesi, çarşamba ve cuma günleri 08:30'da")
        #expect(RoutineSchedule.describe(days: RoutineSchedule.everyDay, hour: 21, minute: 0, language: .english) == "every day at 21:00")
        #expect(RoutineSchedule.describe(days: [0, 2], hour: 8, minute: 30, language: .english) == "on Mondays and Wednesdays at 08:30")
        #expect(RoutineSchedule.describe(routine(RoutineSchedule.everyDay, 21), language: .turkish) == "her gün 21:00'de “hava durumunu söyle”")
    }

    @Test("invalid routines are refused, also when read from a file")
    func validation() throws {
        #expect(Routine(days: [], hour: 8, minute: 0, command: "x") == nil)
        #expect(Routine(days: [7], hour: 8, minute: 0, command: "x") == nil)
        #expect(Routine(days: [1], hour: 24, minute: 0, command: "x") == nil)
        #expect(Routine(days: [1], hour: 8, minute: 0, command: "  ") == nil)
        #expect(Routine(days: [1], hour: 8, minute: 0, command: String(repeating: "a", count: 201)) == nil)
        let original = routine([0, 2], 8, 30)
        let decoded = try JSONDecoder().decode(Routine.self, from: JSONEncoder().encode(original))
        #expect(decoded == original)
        let bad = Data(#"{"id":"\#(UUID().uuidString)","days":[9],"hour":8,"minute":0,"command":"x"}"#.utf8)
        #expect(throws: DecodingError.self) { try JSONDecoder().decode(Routine.self, from: bad) }
    }

    @Test("routines are chosen by part of day or by what they do")
    func choice() {
        let morning = routine(RoutineSchedule.everyDay, 8, 0, "günün özetini oku")
        let evening = routine(RoutineSchedule.everyDay, 21, 0, "hava durumunu söyle")
        let lights = routine(RoutineSchedule.everyDay, 19, 30, "salonun ışığını aç")
        let all = [morning, lights, evening]
        #expect(RoutineChoice.chosen(all, name: "aksam") == [lights])
        #expect(RoutineChoice.chosen(all, name: "gece") == [evening])
        #expect(RoutineChoice.chosen(all, name: "hava durumu") == [evening])
        #expect(RoutineChoice.chosen(all, name: "sabah") == [morning])
        #expect(RoutineChoice.chosen(all, name: "") == all)
        #expect(RoutineChoice.chosen(all, name: "müzik").isEmpty)
    }
}
