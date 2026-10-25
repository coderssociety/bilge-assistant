import Foundation
import Testing
@testable import AsistanCore

@Suite("AppointmentTime")
struct AppointmentTimeTests {
    typealias Moment = AppointmentTime.Moment

    var calendar: Calendar {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "Europe/Istanbul")!
        calendar.firstWeekday = 2
        return calendar
    }

    /// Tuesday, 13 Oct 2026, 09:00
    var morning: Date { calendar.date(from: DateComponents(year: 2026, month: 10, day: 13, hour: 9))! }

    func refine(_ text: String, model: Moment = Moment(dayOffset: nil, hour: nil, minute: nil),
                language: AssistantLanguage = .turkish, at now: Date? = nil) -> Moment {
        let resolved = language == .turkish ? TurkishTimeOfDay.resolve(TurkishNumberParser.digitize(text)) : text
        return AppointmentTime.refine(model, command: resolved, language: language, now: now ?? morning, calendar: calendar)
    }

    @Test("the said day and spoken hour override the model's guesses")
    func spokenHour() {
        #expect(refine("cumartesi saat ikide halı saha maçı ekle", model: Moment(dayOffset: 0, hour: 9, minute: 0))
            == Moment(dayOffset: 4, hour: 14, minute: 0))
        #expect(refine("yarın saat üç buçukta dişçi") == Moment(dayOffset: 1, hour: 15, minute: 30))
        #expect(refine("yarın üçü çeyrek geçe toplantı") == Moment(dayOffset: 1, hour: 15, minute: 15))
        #expect(refine("yarın sabah üçü çeyrek geçe uçak") == Moment(dayOffset: 1, hour: 3, minute: 15))
    }

    @Test("keeps the model's day when the text names none, but drops an invented hour")
    func modelDay() {
        #expect(refine("toplantıyı ekle", model: Moment(dayOffset: 2, hour: 10, minute: 0))
            == Moment(dayOffset: 2, hour: nil, minute: nil))
    }

    @Test("keeps the model's hour when a part of day is named")
    func partOfDay() {
        #expect(refine("akşam ekmek almayı hatırlat", model: Moment(dayOffset: nil, hour: 19, minute: 0))
            == Moment(dayOffset: nil, hour: 19, minute: 0))
    }

    @Test("a time already past today with no day said moves to tomorrow")
    func pastTime() {
        #expect(refine("saat sekizde ilacımı hatırlat") == Moment(dayOffset: 1, hour: 8, minute: 0))
        #expect(refine("saat onda toplantı") == Moment(dayOffset: nil, hour: 10, minute: 0))
        #expect(refine("bugün saat sekizde") == Moment(dayOffset: 0, hour: 8, minute: 0))
    }

    @Test("a duration with 'sonra' is counted from now")
    func duration() {
        #expect(refine("2 saat sonra çamaşırı hatırlat") == Moment(dayOffset: 0, hour: 11, minute: 0))
        #expect(refine("yarım saat sonra hatırlat") == Moment(dayOffset: 0, hour: 9, minute: 30))
        let lateEvening = calendar.date(from: DateComponents(year: 2026, month: 10, day: 13, hour: 23, minute: 30))!
        #expect(refine("1 saat sonra hatırlat", at: lateEvening) == Moment(dayOffset: 1, hour: 0, minute: 30))
    }

    @Test("a duration without 'sonra' is how long it lasts, not when it starts")
    func lengthIsNotStart() {
        #expect(refine("yarın 2 saatlik toplantı ekle") == Moment(dayOffset: 1, hour: nil, minute: nil))
    }

    @Test("English uses the English parsers")
    func english() {
        #expect(refine("remind me in 2 hours", language: .english) == Moment(dayOffset: 0, hour: 11, minute: 0))
        #expect(refine("add a meeting tomorrow at 3", language: .english) == Moment(dayOffset: 1, hour: 15, minute: 0))
    }
}
