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
        ("yarın pazara gitmeyi hatırlat", 1),
        ("yarından sonra dişçi", 2),
        ("cumaya toplantı koy", 3),
        ("cumartesi saat 2'de halı saha", 4),
        ("pazar günü", 5),
        ("haftaya", 7),
        ("gelecek hafta toplantı", 7),
        ("haftaya salı", 7),
        ("haftaya pazartesi ne var", 6),
        ("gelecek hafta cuma", 10),
        ("önümüzdeki hafta perşembe", 9),
        ("2 hafta sonra", 14),
        ("1 hafta sonra", 7),
        ("15 Kasım'da", 33),
        ("3 Aralık toplantı", 51),
        ("10 Ekim", 362),
        ("ayın 20'sinde", 7),
        ("ayın 5'inde", 23),
    ])
    func offsets(text: String, expected: Int) {
        #expect(RelativeDayParser.dayOffset(in: text, now: tuesday, calendar: calendar) == expected)
    }

    @Test("returns nil when no day is mentioned", arguments: [
        "15:00'te toplantı ekle",
        "pazara gitmeyi hatırlat",
        "pazarda domates al",
        "31 Şubat",
    ])
    func none(text: String) {
        #expect(RelativeDayParser.dayOffset(in: text, now: tuesday, calendar: calendar) == nil)
    }

    @Test("tells whether a weekday is named")
    func weekdayNamed() {
        #expect(RelativeDayParser.namesWeekday("haftaya cuma"))
        #expect(!RelativeDayParser.namesWeekday("haftaya ne var"))
        #expect(!RelativeDayParser.namesWeekday("pazara git"))
    }
}
