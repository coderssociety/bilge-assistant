import Testing
@testable import AsistanCore

@Suite("TimerPhraseParser")
struct TimerPhraseParserTests {
    @Test("reads clock times and durations from resolved command text", arguments: [
        ("20:00'de ilacımı hatırlat", TimerPhraseParser.Result(hour: 20, minute: 0, durationSeconds: nil)),
        ("yarın 07:30'da uyandır", TimerPhraseParser.Result(hour: 7, minute: 30, durationSeconds: nil)),
        ("45 dakikalık zamanlayıcı kur", TimerPhraseParser.Result(hour: nil, minute: nil, durationSeconds: 2700)),
        ("1 saat 15 dakika sonra hatırlat", TimerPhraseParser.Result(hour: nil, minute: nil, durationSeconds: 4500)),
        ("30 saniye say", TimerPhraseParser.Result(hour: nil, minute: nil, durationSeconds: 30)),
        ("2 buçuk saat sonra", TimerPhraseParser.Result(hour: nil, minute: nil, durationSeconds: 9000)),
        ("Yarım saat sonra uyar", TimerPhraseParser.Result(hour: nil, minute: nil, durationSeconds: 1800)),
        ("çeyrek saatlik zamanlayıcı", TimerPhraseParser.Result(hour: nil, minute: nil, durationSeconds: 900)),
    ])
    func parses(text: String, expected: TimerPhraseParser.Result) {
        #expect(TimerPhraseParser.parse(text) == expected)
    }

    @Test("reads spoken clock times and fractions of an hour", arguments: [
        ("sekize çeyrek kala uyandır", TimerPhraseParser.Result(hour: 7, minute: 45, durationSeconds: nil)),
        ("dokuzu çeyrek geçe uyandır", TimerPhraseParser.Result(hour: 9, minute: 15, durationSeconds: nil)),
        ("üç çeyrek sonra uyar", TimerPhraseParser.Result(hour: nil, minute: nil, durationSeconds: 2700)),
        ("üç çeyrek saat sonra", TimerPhraseParser.Result(hour: nil, minute: nil, durationSeconds: 2700)),
        ("bir buçuk saat sonra", TimerPhraseParser.Result(hour: nil, minute: nil, durationSeconds: 5400)),
        ("bir buçuk dakikalık zamanlayıcı", TimerPhraseParser.Result(hour: nil, minute: nil, durationSeconds: 90)),
        ("yarım saat sonra", TimerPhraseParser.Result(hour: nil, minute: nil, durationSeconds: 1800)),
    ])
    func parsesSpoken(text: String, expected: TimerPhraseParser.Result) {
        #expect(TimerPhraseParser.parse(TurkishTimeOfDay.resolve(TurkishNumberParser.digitize(text))) == expected)
    }

    @Test("an appointment at a 12-hour 1-6 o'clock is in the afternoon; padded and alarm times stay")
    func appointment() {
        #expect(TimerPhraseParser.parse("3:15 toplantı", appointment: true)?.hour == 15)
        #expect(TimerPhraseParser.parse("3:15 toplantı")?.hour == 3)
        #expect(TimerPhraseParser.parse("03:15 toplantı", appointment: true)?.hour == 3)
        #expect(TimerPhraseParser.parse("9:15 toplantı", appointment: true)?.hour == 9)
    }

    @Test("returns nil when nothing precise is said")
    func nothing() {
        #expect(TimerPhraseParser.parse("çay için zamanlayıcı kur") == nil)
        #expect(TimerPhraseParser.parse("çeyrek final maçını hatırlat") == nil)
    }

    @Test("reads spoken hours for appointments, afternoon for 1 to 6 unless morning is said", arguments: [
        ("cumartesi saat ikide halı saha maçı ekle", 14, 0),
        ("saat dokuzda toplantı", 9, 0),
        ("saat on dörtte", 14, 0),
        ("iki buçukta dişçi", 14, 30),
        ("saat üç buçukta", 15, 30),
        ("yarın 10'da kuaför", 10, 0),
        ("sabah saat beşte uçak", 5, 0),
        ("akşam sekizde yemek", 20, 0),
        ("akşam saat sekizde yemek", 20, 0),
        ("sabah yedide koşu", 7, 0),
        ("öğlen annemle yemek", 12, 0),
    ])
    func appointmentHours(text: String, hour: Int, minute: Int) {
        let resolved = TurkishTimeOfDay.resolve(TurkishNumberParser.digitize(text))
        #expect(TimerPhraseParser.parse(resolved, appointment: true) == .init(hour: hour, minute: minute, durationSeconds: nil))
    }

    @Test("keeps durations and dates apart from spoken hours", arguments: [
        ("1 saat 15 dakika sonra hatırlat", TimerPhraseParser.Result(hour: nil, minute: nil, durationSeconds: 4500)),
        ("2 saat sonra hatırlat", TimerPhraseParser.Result(hour: nil, minute: nil, durationSeconds: 7200)),
        ("2 buçuk saat sonra", TimerPhraseParser.Result(hour: nil, minute: nil, durationSeconds: 9000)),
    ])
    func appointmentDurations(text: String, expected: TimerPhraseParser.Result) {
        #expect(TimerPhraseParser.parse(text, appointment: true) == expected)
    }

    @Test("dates are not hours", arguments: ["15 Kasım'da toplantı", "ayın 20'sinde kira", "3 Aralık'ta"])
    func datesAreNotHours(text: String) {
        #expect(TimerPhraseParser.parse(text, appointment: true) == nil)
    }

    @Test("alarms and timers do not read spoken hours")
    func notForAlarms() {
        #expect(TimerPhraseParser.parse("saat 2'de uyandır") == nil)
    }
}
