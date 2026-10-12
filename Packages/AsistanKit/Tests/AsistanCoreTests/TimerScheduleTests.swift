import Foundation
import Testing
@testable import AsistanCore

@Suite("TimerSchedule")
struct TimerScheduleTests {
    var calendar: Calendar {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "Europe/Istanbul")!
        return calendar
    }

    /// 13 Oct 2026 14:00 Istanbul
    var now: Date { calendar.date(from: DateComponents(year: 2026, month: 10, day: 13, hour: 14))! }

    @Test("durations add minutes and seconds")
    func duration() {
        let date = TimerSchedule.fireDate(minutes: 10, seconds: 30, hour: nil, minute: nil, now: now, calendar: calendar)
        #expect(date == now.addingTimeInterval(630))
    }

    @Test("a clock time later today fires today")
    func laterToday() {
        let date = TimerSchedule.fireDate(minutes: nil, seconds: nil, hour: 18, minute: 30, now: now, calendar: calendar)
        #expect(date == calendar.date(from: DateComponents(year: 2026, month: 10, day: 13, hour: 18, minute: 30)))
    }

    @Test("a clock time already passed fires tomorrow")
    func passedTime() {
        let date = TimerSchedule.fireDate(minutes: nil, seconds: nil, hour: 7, minute: nil, now: now, calendar: calendar)
        #expect(date == calendar.date(from: DateComponents(year: 2026, month: 10, day: 14, hour: 7)))
    }

    @Test("clock time wins over a duration when both are given")
    func clockWins() {
        let date = TimerSchedule.fireDate(minutes: 5, seconds: nil, hour: 18, minute: 0, now: now, calendar: calendar)
        #expect(date == calendar.date(from: DateComponents(year: 2026, month: 10, day: 13, hour: 18)))
    }

    @Test("rejects empty, zero, negative, too long or out-of-range input", arguments: [
        (nil, nil, nil, nil), (0, 0, nil, nil), (-5, nil, nil, nil), (1500, nil, nil, nil),
        (nil, nil, 24, 0), (nil, nil, 7, 75),
    ] as [(Int?, Int?, Int?, Int?)])
    func rejects(minutes: Int?, seconds: Int?, hour: Int?, minute: Int?) {
        #expect(TimerSchedule.fireDate(minutes: minutes, seconds: seconds, hour: hour, minute: minute,
                                       now: now, calendar: calendar) == nil)
    }

    @Test("labels are trimmed to a short phrase")
    func labels() {
        #expect(TimerSchedule.cleanLabel("  çay  ") == "çay")
        #expect(TimerSchedule.cleanLabel("") == nil)
        #expect(TimerSchedule.cleanLabel(String(repeating: "uzun ", count: 30))?.count ?? 0 <= 40)
    }
}
