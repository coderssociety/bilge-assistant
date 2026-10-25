import Foundation
import Testing
@testable import AsistanCore

@Suite("WeatherQuestion")
struct WeatherQuestionTests {
    typealias Focus = WeatherQuestion.Focus

    var calendar: Calendar {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "Europe/Istanbul")!
        calendar.firstWeekday = 2
        return calendar
    }

    /// Tuesday, 13 Oct 2026
    func tuesday(hour: Int) -> Date {
        calendar.date(from: DateComponents(year: 2026, month: 10, day: 13, hour: hour))!
    }

    func focus(_ text: String, model: Int? = nil, language: AssistantLanguage = .turkish, hour: Int = 9) -> Focus {
        WeatherQuestion.focus(in: text, modelDayOffset: model, language: language, now: tuesday(hour: hour), calendar: calendar)
    }

    @Test("reads the day from the words, keeping the model's only when none is said")
    func day() {
        #expect(focus("peki yarın?", model: 0) == Focus(dayOffset: 1, partOfDay: nil, asksAboutRain: false))
        #expect(focus("cuma hava nasıl olacak") == Focus(dayOffset: 3, partOfDay: nil, asksAboutRain: false))
        #expect(focus("İzmir'de hava nasıl") == Focus(dayOffset: nil, partOfDay: nil, asksAboutRain: false))
        #expect(focus("hava nasıl", model: 2) == Focus(dayOffset: 2, partOfDay: nil, asksAboutRain: false))
    }

    @Test("a rain question with no day is about today")
    func rain() {
        #expect(focus("yağmur yağacak mı") == Focus(dayOffset: 0, partOfDay: nil, asksAboutRain: true))
        #expect(focus("şemsiye alayım mı") == Focus(dayOffset: 0, partOfDay: nil, asksAboutRain: true))
        #expect(focus("yarın kar yağar mı") == Focus(dayOffset: 1, partOfDay: nil, asksAboutRain: true))
        #expect(focus("will it rain", language: .english) == Focus(dayOffset: 0, partOfDay: nil, asksAboutRain: true))
    }

    @Test("reads the part of the day asked about", arguments: [
        ("akşam yağmur var mı", Focus(dayOffset: 0, partOfDay: .evening, asksAboutRain: true)),
        ("öğleden sonra hava nasıl", Focus(dayOffset: 0, partOfDay: .afternoon, asksAboutRain: false)),
        ("yarın sabah hava nasıl", Focus(dayOffset: 1, partOfDay: .morning, asksAboutRain: false)),
        ("bu gece kaç derece", Focus(dayOffset: 0, partOfDay: .night, asksAboutRain: false)),
        ("geçen hafta hava nasıldı", Focus(dayOffset: nil, partOfDay: nil, asksAboutRain: false)),
    ])
    func partOfDay(text: String, expected: Focus) {
        #expect(focus(text) == expected)
    }

    @Test("a part of day already over today is about tomorrow")
    func pastPart() {
        #expect(focus("sabah yağmur var mı", hour: 15) == Focus(dayOffset: 1, partOfDay: .morning, asksAboutRain: true))
        #expect(focus("bugün sabah yağmur var mıydı", hour: 15) == Focus(dayOffset: 0, partOfDay: .morning, asksAboutRain: true))
        #expect(focus("what about this evening", language: .english, hour: 15)
            == Focus(dayOffset: 0, partOfDay: .evening, asksAboutRain: false))
    }

    @Test("remembers the city of a weather answer for a short while")
    func followUp() {
        var memory = WeatherFollowUp()
        let now = tuesday(hour: 9)
        memory.remember(city: "İzmir", at: now)
        #expect(memory.city(at: now.addingTimeInterval(60)) == "İzmir")
        #expect(memory.city(at: now.addingTimeInterval(WeatherFollowUp.window + 1)) == nil)
        #expect(WeatherFollowUp().city(at: now) == nil)
    }
}

@Suite("WeatherReport hours")
struct WeatherReportHoursTests {
    /// Two days of hourly values: 10 degrees at midnight rising one degree an hour; rain in the evening.
    let temperatures = (0..<48).map { Double(10 + $0 % 24) }
    let codes = (0..<48).map { $0 % 24 >= 18 ? 63 : 1 }
    let rainChances: [Int?] = (0..<48).map { $0 % 24 >= 18 ? 80 : 5 }

    @Test("summarizes the hours of the asked part of a day")
    func window() {
        let evening = WeatherReport.window(hours: 18..<22, dayOffset: 1, temperatures: temperatures, codes: codes, rainChances: rainChances)
        #expect(evening == WeatherReport.HourlyWindow(minimum: 28, maximum: 31, code: 63, rainChance: 80))
        let morning = WeatherReport.window(hours: 6..<12, dayOffset: 0, temperatures: temperatures, codes: codes, rainChances: rainChances)
        #expect(morning == WeatherReport.HourlyWindow(minimum: 16, maximum: 21, code: 1, rainChance: 5))
        #expect(WeatherReport.window(hours: 6..<12, dayOffset: 2, temperatures: temperatures, codes: codes, rainChances: rainChances) == nil)
    }

    @Test("says the part of the day and the rain chance when rain was asked")
    func sentences() {
        let window = WeatherReport.HourlyWindow(minimum: 14.2, maximum: 16.4, code: 63, rainChance: 70)
        #expect(WeatherReport.partOfDay(city: "İzmir", dayName: "bugün", part: .evening, window: window, mentionRain: true)
            == "İzmir'de bugün akşam hava yağmurlu, sıcaklık 14 ile 16 derece arasında. Yağış ihtimali yüzde 70.")
        #expect(WeatherReport.partOfDay(city: "Paris", dayName: "today", part: .evening, window: window, mentionRain: false,
                                        language: .english)
            == "In Paris this evening it will be rainy, between 14 and 16 degrees. There's a 70 percent chance of rain.")
        #expect(WeatherReport.daily(city: "Ankara", dayName: "bugün", minimum: 8, maximum: 15, code: 1, rainChance: 10, mentionRain: true)
            == "Ankara'da bugün hava çoğunlukla açık, sıcaklık 8 ile 15 derece arasında. Yağış ihtimali yüzde 10.")
    }
}
