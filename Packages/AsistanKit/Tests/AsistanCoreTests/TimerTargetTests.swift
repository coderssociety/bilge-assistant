import Testing
@testable import AsistanCore

@Suite("TimerTarget")
struct TimerTargetTests {
    func parse(_ text: String, _ language: AssistantLanguage = .turkish) -> TimerTarget? {
        TimerTarget.parse(TurkishNumberParser.digitize(text), language: language)
    }

    @Test("reads which timer a Turkish cancel request means", arguments: [
        ("çay zamanlayıcısını iptal et", TimerTarget.label("cay")),
        ("lütfen çay için kurduğum alarmı sil", .label("cay")),
        ("zamanlayıcıyı iptal et", .any),
        ("alarmı kapat", .any),
        ("ikinci zamanlayıcıyı iptal et", .position(2)),
        ("ilk alarmı sil", .position(1)),
        ("son zamanlayıcıyı kapat", .position(-1)),
        ("bütün alarmları sil", .all),
        ("zamanlayıcıları iptal et", .all),
        ("hepsini iptal et", .all),
        ("onu iptal et", .any),
    ])
    func turkish(text: String, expected: TimerTarget) {
        #expect(parse(text) == expected)
    }

    @Test("reads which timer an English cancel request means", arguments: [
        ("cancel the tea timer", TimerTarget.label("tea")),
        ("cancel the timer for pasta", .label("pasta")),
        ("stop the timer", .any),
        ("delete my second alarm", .position(2)),
        ("cancel the 3rd timer", .position(3)),
        ("cancel all timers", .all),
        ("delete the alarms", .all),
    ])
    func english(text: String, expected: TimerTarget) {
        #expect(parse(text, .english) == expected)
    }

    @Test("is nil when nothing is cancelled", arguments: ["kaç dakika kaldı", "kurulu zamanlayıcılar neler", "çay için zamanlayıcı kur"])
    func notCancel(text: String) {
        #expect(parse(text) == nil)
    }

    @Test("selects one timer, or none, or asks which")
    func select() {
        let labels: [String?] = ["Çay", nil, "çamaşır"]
        #expect(TimerTarget.select(.label("cay"), labels: labels) == .timer(0))
        #expect(TimerTarget.select(.label("çayın"), labels: labels) == .timer(0))
        #expect(TimerTarget.select(.label("fırın"), labels: labels) == .noMatch)
        #expect(TimerTarget.select(.label("ça"), labels: labels) == .ambiguous)
        #expect(TimerTarget.select(.position(2), labels: labels) == .timer(1))
        #expect(TimerTarget.select(.position(-1), labels: labels) == .timer(2))
        #expect(TimerTarget.select(.position(4), labels: labels) == .noMatch)
        #expect(TimerTarget.select(.any, labels: labels) == .ambiguous)
        #expect(TimerTarget.select(.any, labels: ["çay"]) == .timer(0))
        #expect(TimerTarget.select(.any, labels: []) == .noMatch)
    }
}
