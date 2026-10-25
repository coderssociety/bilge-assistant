import Testing
@testable import AsistanCore

@Suite("RoutineRequest")
struct RoutineRequestTests {
    @Test("Turkish routines are read with their days, time and command", arguments: [
        ("her gece 21'de hava durumunu söyle", RoutineRequest(days: RoutineSchedule.everyDay, hour: 21, minute: 0, command: "hava durumunu söyle")),
        ("her sabah 8'de günün özetini oku", RoutineRequest(days: RoutineSchedule.everyDay, hour: 8, minute: 0, command: "günün özetini oku")),
        ("hafta içi her gün 7'de haberleri oku", RoutineRequest(days: RoutineSchedule.weekdays, hour: 7, minute: 0, command: "haberleri oku")),
        ("her akşam yedi buçukta salonun ışığını aç", RoutineRequest(days: RoutineSchedule.everyDay, hour: 19, minute: 30, command: "salonun ışığını aç")),
        ("her gece on birde ışıkları kapat", RoutineRequest(days: RoutineSchedule.everyDay, hour: 23, minute: 0, command: "ışıkları kapat")),
        ("hava durumunu her gece 21de söyle", RoutineRequest(days: RoutineSchedule.everyDay, hour: 21, minute: 0, command: "hava durumunu söyle")),
        ("hafta sonları saat 10'da hava durumunu söyle", RoutineRequest(days: RoutineSchedule.weekend, hour: 10, minute: 0, command: "hava durumunu söyle")),
        ("her pazartesi saat dokuzda haberleri oku", RoutineRequest(days: [0], hour: 9, minute: 0, command: "haberleri oku")),
        ("pazartesi ve çarşamba günleri sabah 9'da haberleri oku", RoutineRequest(days: [0, 2], hour: 9, minute: 0, command: "haberleri oku")),
        ("cumartesileri 10'da hava durumunu söyle", RoutineRequest(days: [5], hour: 10, minute: 0, command: "hava durumunu söyle")),
        ("her gün saat 3'te ilaçlarımı hatırlat", RoutineRequest(days: RoutineSchedule.everyDay, hour: 15, minute: 0, command: "ilaçlarımı hatırlat")),
    ])
    func turkish(said: String, expected: RoutineRequest) {
        #expect(RoutineRequest.parse(said, language: .turkish) == expected)
    }

    @Test("Turkish requests that are not a whole routine are left alone", arguments: [
        "saat kaç",
        "yarın 7'de alarm kur",
        // One Saturday or Monday is a reminder, not a routine.
        "cumartesi 10'da bana su içmeyi hatırlat",
        "pazartesi 9'da haberleri oku",
        "her sabah haberleri oku",
        "her gün 9'da",
        // Talking about the routine itself is not a request for one.
        "her gün 9'da haberleri okuyan bir rutin kur",
        "rutinlerim neler",
    ])
    func turkishNonRoutines(said: String) {
        #expect(RoutineRequest.parse(said, language: .turkish) == nil)
    }

    @Test("English routines", arguments: [
        ("every night at 9 tell me the weather", RoutineRequest(days: RoutineSchedule.everyDay, hour: 21, minute: 0, command: "tell me the weather")),
        ("every weekday at 7 read the news", RoutineRequest(days: RoutineSchedule.weekdays, hour: 7, minute: 0, command: "read the news")),
        ("read the news every weekday at 7 am", RoutineRequest(days: RoutineSchedule.weekdays, hour: 7, minute: 0, command: "read the news")),
        ("at 8:30 every monday and wednesday, read my calendar", RoutineRequest(days: [0, 2], hour: 8, minute: 30, command: "read my calendar")),
        ("on weekends at 10 tell me the weather", RoutineRequest(days: RoutineSchedule.weekend, hour: 10, minute: 0, command: "tell me the weather")),
        ("every morning at 8 read the daily briefing", RoutineRequest(days: RoutineSchedule.everyDay, hour: 8, minute: 0, command: "read the daily briefing")),
    ])
    func english(said: String, expected: RoutineRequest) {
        #expect(RoutineRequest.parse(said, language: .english) == expected)
    }

    @Test("English requests that are not routines", arguments: [
        "on monday at 9 read the news", "set a timer for 10 minutes", "what time is it", "remind me on saturday at 10 to drink water",
    ])
    func englishNonRoutines(said: String) {
        #expect(RoutineRequest.parse(said, language: .english) == nil)
    }

    @Test("asking for the routines")
    func list() {
        #expect(RoutineRequest.asksForList("rutinlerim neler", language: .turkish))
        #expect(RoutineRequest.asksForList("rutinlerim", language: .turkish))
        #expect(RoutineRequest.asksForList("hangi rutinler var", language: .turkish))
        #expect(!RoutineRequest.asksForList("akşam rutinini sil", language: .turkish))
        #expect(!RoutineRequest.asksForList("haberleri oku", language: .turkish))
        #expect(RoutineRequest.asksForList("what are my routines", language: .english))
        #expect(!RoutineRequest.asksForList("delete the evening routine", language: .english))
    }

    @Test("deleting a routine by name, or all of them")
    func removal() {
        #expect(RoutineRequest.removal("akşam rutinini sil", language: .turkish) == .init(name: "aksam"))
        #expect(RoutineRequest.removal("hava durumu rutinini iptal et", language: .turkish) == .init(name: "hava durumu"))
        #expect(RoutineRequest.removal("hava durumu rutinini kaldır", language: .turkish) == .init(name: "hava durumu"))
        #expect(RoutineRequest.removal("bütün rutinleri sil", language: .turkish) == .init(name: "", every: true))
        #expect(RoutineRequest.removal("rutinleri sil", language: .turkish) == .init(name: "", every: true))
        #expect(RoutineRequest.removal("rutinlerim neler", language: .turkish) == nil)
        #expect(RoutineRequest.removal("delete the evening routine", language: .english) == .init(name: "evening"))
        #expect(RoutineRequest.removal("remove all routines", language: .english) == .init(name: "", every: true))
    }
}
