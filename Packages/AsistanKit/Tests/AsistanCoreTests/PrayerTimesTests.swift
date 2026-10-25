import Foundation
import Testing
@testable import AsistanCore

@Suite("PrayerTimes")
struct PrayerTimesTests {
    var calendar: Calendar {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = PrayerTimesParser.turkeyTimeZone
        calendar.firstWeekday = 2
        return calendar
    }

    /// Sunday, 25 Oct 2026, the first day in the Diyanet sample.
    func sunday(hour: Int, minute: Int = 0) -> Date {
        calendar.date(from: DateComponents(year: 2026, month: 10, day: 25, hour: hour, minute: minute))!
    }

    func parse(_ text: String, language: AssistantLanguage = .turkish, hour: Int = 16) -> PrayerQuestion? {
        PrayerQuestion.parse(text, language: language, now: sunday(hour: hour), calendar: calendar)
    }

    func answer(_ text: String, language: AssistantLanguage = .turkish, hour: Int = 16, minute: Int = 0) -> String? {
        guard let question = parse(text, language: language, hour: hour) else { return nil }
        let days = PrayerTimesParser.diyanetDays(from: PrayerFixtures.diyanetMonth)
        return PrayerReport.text(question, days: days, city: "Ankara", now: sunday(hour: hour, minute: minute), language: language)
    }

    @Test("reads the Diyanet month and skips a malformed day")
    func diyanetMonth() throws {
        let days = PrayerTimesParser.diyanetDays(from: PrayerFixtures.diyanetMonth)
        #expect(days.count == 2)
        let first = try #require(days.first)
        #expect((first.year, first.month, first.day) == (2026, 10, 25))
        #expect(first.minutes[.imsak] == 5 * 60 + 39)
        #expect(first.minutes[.maghrib] == 18 * 60 + 3)
        #expect(first.date(of: .isha) == sunday(hour: 19, minute: 22))
    }

    @Test("finds the province's city and its centre district")
    func ids() {
        let ankara = TurkishProvince.named("Ankara")!
        #expect(PrayerTimesParser.cityID(for: ankara, in: PrayerFixtures.diyanetCities) == "506")
        #expect(PrayerTimesParser.cityID(for: TurkishProvince.named("istanbul")!, in: PrayerFixtures.diyanetCities) == "539")
        #expect(PrayerTimesParser.centreDistrictID(for: ankara, in: PrayerFixtures.diyanetDistricts) == "9206")
        #expect(PrayerTimesParser.cityID(for: ankara, in: Data("not json".utf8)) == nil)
    }

    @Test("Aladhan's Fajr is Diyanet's imsak")
    func aladhan() throws {
        let day = try #require(PrayerTimesParser.aladhanDay(from: PrayerFixtures.aladhanDay))
        #expect(day.minutes[.imsak] == 5 * 60 + 39)
        #expect(day.minutes[.maghrib] == 18 * 60 + 2)
        #expect(day.timeZone.identifier == "Europe/Istanbul")
        #expect(PrayerTimesParser.aladhanDay(from: Data(#"{"code":503,"data":"Geocoding is temporarily unavailable."}"#.utf8)) == nil)
    }

    @Test("understands which time is asked", arguments: [
        ("akşam ezanı kaçta", PrayerQuestion(prayer: .maghrib)),
        ("ezana ne kadar var", PrayerQuestion(prayer: nil)),
        ("iftara kaç dakika kaldı", PrayerQuestion(prayer: .maghrib, naming: .iftar)),
        ("yarın imsak kaçta", PrayerQuestion(prayer: .imsak, dayOffset: 1)),
        ("bugünkü namaz vakitleri", PrayerQuestion(prayer: nil, dayOffset: 0, listsAll: true)),
        ("Ankara'da öğle ezanı", PrayerQuestion(prayer: .dhuhr)),
        ("sahur ne zaman bitiyor", PrayerQuestion(prayer: .imsak, naming: .sahur)),
        ("bu akşam yatsı kaçta", PrayerQuestion(prayer: .isha)),
        ("cuma namazı kaçta", PrayerQuestion(prayer: .dhuhr, dayOffset: 5)),
    ])
    func turkishQuestions(text: String, expected: PrayerQuestion) {
        #expect(parse(text) == expected)
    }

    @Test("leaves reminders, alarms and other iftar talk alone", arguments: [
        "akşam ezanından önce hatırlat", "sahur için alarm kur", "iftar menüsü öner", "ezan sesi", "akşam yemeği kaçta",
        "iftara arkadaşlar gelecek takvime ekle", "Ezan Vakti uygulamasını aç",
    ])
    func notPrayerQuestions(text: String) {
        #expect(parse(text) == nil)
    }

    @Test("English questions", arguments: [
        ("when is maghrib", PrayerQuestion(prayer: .maghrib)),
        ("how long until iftar", PrayerQuestion(prayer: .maghrib, naming: .iftar)),
        ("prayer times for tomorrow", PrayerQuestion(prayer: nil, dayOffset: 1, listsAll: true)),
        ("what time is the next prayer", PrayerQuestion(prayer: nil)),
    ])
    func englishQuestions(text: String, expected: PrayerQuestion) {
        #expect(parse(text, language: .english) == expected)
    }

    @Test("English reminders are not claimed")
    func englishReminder() {
        #expect(parse("remind me before maghrib", language: .english) == nil)
        #expect(parse("what time is it", language: .english) == nil)
    }

    @Test("an upcoming time comes with what is left")
    func upcoming() {
        #expect(answer("akşam ezanı kaçta") == "Ankara'da akşam ezanı 18:03'te, 2 saat 3 dakika kaldı.")
        #expect(answer("iftara kaç dakika kaldı", minute: 30) == "Ankara'da iftar 18:03'te, 1 saat 33 dakika kaldı.")
        #expect(answer("ezana ne kadar var") == "Ankara'da sıradaki vakit akşam, 18:03'te; 2 saat 3 dakika kaldı.")
    }

    @Test("a time already past today is given for tomorrow, unless today was asked")
    func passed() {
        #expect(answer("akşam ezanı kaçta", hour: 20) == "Ankara'da akşam ezanı yarın 18:02'de, 22 saat 2 dakika kaldı.")
        #expect(answer("ezana ne kadar var", hour: 20) == "Ankara'da sıradaki vakit yarın imsak, 05:40'ta; 9 saat 40 dakika kaldı.")
        #expect(answer("bugün öğle ezanı kaçtaydı") == "Ankara'da bugün öğle ezanı 12:38'deydi.")
    }

    @Test("another day and the whole list")
    func otherDays() {
        #expect(answer("yarın imsak kaçta") == "Ankara'da yarın imsak 05:40'ta.")
        #expect(answer("bugünkü namaz vakitleri")
            == "Ankara'da bugün imsak 05:39, güneş 07:02, öğle 12:38, ikindi 15:34, akşam 18:03, yatsı 19:22.")
        #expect(answer("prayer times for tomorrow", language: .english)
            == "Prayer times in Ankara tomorrow: Fajr 05:40, sunrise 07:03, Dhuhr 12:38, Asr 15:33, Maghrib 18:02, Isha 19:20.")
        #expect(answer("when is maghrib", language: .english) == "In Ankara, Maghrib is at 18:03, in 2 hours 3 minutes.")
    }

    @Test("days missing from the list give no answer, so a newer list is fetched")
    func missingDays() {
        let days = PrayerTimesParser.diyanetDays(from: PrayerFixtures.diyanetMonth)
        let later = calendar.date(from: DateComponents(year: 2026, month: 11, day: 3, hour: 9))!
        #expect(PrayerReport.text(PrayerQuestion(prayer: .maghrib), days: days, city: "Ankara", now: later, language: .turkish) == nil)
        #expect(PrayerReport.text(PrayerQuestion(prayer: .imsak, dayOffset: 4), days: days, city: "Ankara",
                                  now: sunday(hour: 9), language: .turkish) == nil)
    }
}
