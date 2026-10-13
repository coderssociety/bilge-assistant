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

    @Test("returns nil when nothing precise is said")
    func nothing() {
        #expect(TimerPhraseParser.parse("çay için zamanlayıcı kur") == nil)
    }
}
