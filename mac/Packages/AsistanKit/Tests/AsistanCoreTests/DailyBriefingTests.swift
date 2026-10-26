import Foundation
import Testing
@testable import AsistanCore

@Suite("DailyBriefing")
struct DailyBriefingTests {
    private var calendar: Calendar {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "Europe/Istanbul")!
        return calendar
    }

    private func date(_ hour: Int, _ minute: Int = 0) -> Date {
        calendar.date(from: DateComponents(year: 2026, month: 10, day: 14, hour: hour, minute: minute))!
    }

    @Test("requests for the day's summary", arguments: [
        "Günün özeti", "Bugün neler var", "Bana günü özetle", "Sabah özetini ver", "Bugün beni neler bekliyor",
    ])
    func requests(text: String) {
        #expect(BriefingIntent.isRequest(text))
    }

    @Test("not a summary request", arguments: ["Bugün hava nasıl", "Bugün takvimimde ne var", "Günaydın", "Bu akşam ne var"])
    func notRequests(text: String) {
        #expect(!BriefingIntent.isRequest(text))
    }

    @Test("a morning greeting on its own")
    func greeting() {
        #expect(BriefingIntent.isMorningGreeting("Günaydın"))
        #expect(BriefingIntent.isMorningGreeting("günaydın Bilge"))
        #expect(!BriefingIntent.isMorningGreeting("Günaydın, saat kaç"))
    }

    @Test("everything there is, in a few sentences")
    func full() {
        let briefing = DailyBriefing(
            now: date(8, 30), weather: "İstanbul'da bugün hava güneşli, 18 ile 24 derece arasında.",
            events: [.init(title: "Ekip toplantısı", start: date(10)), .init(title: "Diş hekimi", start: date(15, 30))],
            reminders: ["Faturayı öde"], unreadMail: 4)
        #expect(briefing.text(calendar: calendar) == "Günaydın. Bugün 14 Ekim Çarşamba. İstanbul'da bugün hava güneşli, 18 ile 24 derece arasında. "
            + "Bugün 2 etkinliğin var: 10:00'da Ekip toplantısı, 15:30'da Diş hekimi. Bugünkü anımsatıcın: Faturayı öde. 4 okunmamış e-postan var.")
    }

    @Test("a quiet day and a long list")
    func quietAndLong() {
        let quiet = DailyBriefing(now: date(19), weather: nil, events: [], reminders: [], unreadMail: 0)
        #expect(quiet.text(calendar: calendar) == "İyi akşamlar. Bugün 14 Ekim Çarşamba. Bugün başka etkinliğin yok.")
        let busy = DailyBriefing(
            now: date(13), weather: nil,
            events: (9...14).map { .init(title: "Görüşme \($0)", start: date($0 + 1)) },
            reminders: ["A", "B", "C"], unreadMail: nil)
        #expect(busy.text(calendar: calendar) == "İyi günler. Bugün 14 Ekim Çarşamba. "
            + "Bugün 6 etkinliğin var: 10:00'da Görüşme 9, 11:00'de Görüşme 10, 12:00'de Görüşme 11 ve 3 tane daha. "
            + "3 anımsatıcın var: A, B ve 1 tane daha.")
    }

    @Test("an unreadable calendar is not a free day")
    func unreadableCalendar() {
        let briefing = DailyBriefing(now: date(9), weather: nil, events: nil, reminders: [], unreadMail: nil)
        #expect(briefing.text(calendar: calendar) == "Günaydın. Bugün 14 Ekim Çarşamba. Takvimini okuyamadım.")
        #expect(briefing.text(calendar: calendar, language: .english).hasSuffix("I couldn't read your calendar."))
    }

    @Test("the locative ending follows the time as spoken", arguments: [
        (10, 0, "10:00'da"), (11, 0, "11:00'de"), (13, 0, "13:00'te"), (16, 0, "16:00'da"), (15, 30, "15:30'da"),
        (15, 40, "15:40'ta"), (9, 20, "09:20'de"), (0, 0, "00:00'da"), (14, 45, "14:45'te"), (8, 50, "08:50'de"),
        (19, 9, "19:09'da"), (20, 0, "20:00'de"),
    ])
    func timeEndings(hour: Int, minute: Int, expected: String) {
        #expect(TurkishGrammar.timeLocative(hour: hour, minute: minute) == expected)
    }
}
