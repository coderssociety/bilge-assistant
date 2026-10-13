import Foundation
import Testing
@testable import AsistanCore

@Suite("RelativeDayParser")
struct RelativeDayParserTests {
    var calendar: Calendar {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "Europe/Istanbul")!
        calendar.firstWeekday = 2
        return calendar
    }

    /// Tuesday, 13 Oct 2026
    var tuesday: Date { calendar.date(from: DateComponents(year: 2026, month: 10, day: 13, hour: 9))! }

    @Test("resolves relative day words to a day offset", arguments: [
        ("bugün saat 15:00'te toplantı", 0),
        ("yarın 10:00'da diş hekimi", 1),
        ("öbür gün sabah", 2),
        ("ertesi gün", 1),
        ("cuma günü toplantı ekle", 3),
        ("Pazartesi annemi ara", 6),
        ("salı günü", 7),
        ("haftaya çarşamba", 8),
        ("3 gün sonra", 3),
    ])
    func offsets(text: String, expected: Int) {
        #expect(RelativeDayParser.dayOffset(in: text, now: tuesday, calendar: calendar) == expected)
    }

    @Test("returns nil when no day is mentioned")
    func none() {
        #expect(RelativeDayParser.dayOffset(in: "15:00'te toplantı ekle", now: tuesday, calendar: calendar) == nil)
    }
}
