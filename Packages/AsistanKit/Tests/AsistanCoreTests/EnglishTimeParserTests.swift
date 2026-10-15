import Foundation
import Testing
@testable import AsistanCore

@Suite("English days and times")
struct EnglishTimeParserTests {
    /// Thursday 15 October 2026.
    private let now = Calendar(identifier: .gregorian).date(from: DateComponents(year: 2026, month: 10, day: 15, hour: 9))!

    @Test("days", arguments: [
        ("tomorrow at ten", Int?.some(1)), ("the day after tomorrow", 2), ("on Friday", 1), ("next Friday", 8),
        ("on Thursday", 7), ("in 3 days", 3), ("in three days", 3), ("today at noon", 0), ("set a timer", nil),
    ])
    func days(text: String, expected: Int?) {
        #expect(EnglishTimeParser.dayOffset(in: text, now: now, calendar: Calendar(identifier: .gregorian)) == expected)
    }

    @Test("clock times", arguments: [
        ("Add a dentist appointment tomorrow at ten", 10, 0), ("meeting at 3", 15, 0), ("at 10:30", 10, 30),
        ("at 7 pm", 19, 0), ("at 7:15 p.m.", 19, 15), ("12 am", 0, 0), ("lunch at noon", 12, 0), ("dinner at eight tonight", 20, 0),
        ("Set an alarm for 6:30", 6, 30), ("At a dentist appointment tomorrow at 10", 10, 0),
    ])
    func clock(text: String, hour: Int, minute: Int) {
        let result = EnglishTimeParser.parse(text)
        #expect(result?.hour == hour)
        #expect(result?.minute == minute)
    }

    @Test("alarms keep the hour as said")
    func alarms() {
        #expect(EnglishTimeParser.parse("wake me up at 6", appointment: false)?.hour == 6)
        #expect(EnglishTimeParser.parse("remind me at 9 tonight", appointment: false)?.hour == 21)
    }

    @Test("durations", arguments: [
        ("Set a timer for 10 minutes", 600), ("in an hour", 3600), ("for half an hour", 1800),
        ("1 hour 15 minutes", 4500), ("forty five seconds", 45), ("in twenty minutes", 1200),
    ])
    func durations(text: String, seconds: Int) {
        #expect(EnglishTimeParser.parse(text)?.durationSeconds == seconds)
    }

    @Test("nothing to read")
    func none() {
        #expect(EnglishTimeParser.parse("Add milk to my list") == nil)
        #expect(EnglishTimeParser.parse("Turn the volume to 30 percent") == nil)
    }
}
