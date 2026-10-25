import Foundation
import Testing
@testable import AsistanCore

@Suite("WorldClock")
struct WorldClockTests {
    /// Wednesday 15 July 2026, 15:00 in Istanbul.
    private let now = Date(timeIntervalSince1970: 1_784_116_800)
    private let istanbul = TimeZone(identifier: "Europe/Istanbul")!

    @Test("answers Turkish questions", arguments: [
        ("Tokyo'da saat kaç", "Tokyo'da saat 21:00. Senden 6 saat ileride."),
        ("Londra'da şu an saat kaç", "Londra'da saat 13:00. Senden 2 saat geride."),
        ("New York ile aramızda kaç saat fark var", "New York, senden 7 saat geride. Orada saat 08:00."),
        ("Yeni Delhi'de saat kaç", "Yeni Delhi'de saat 17:30. Senden 2 buçuk saat ileride."),
        ("Katmandu'da saat kaç", "Katmandu'da saat 17:45. Senden 2 saat 45 dakika ileride."),
        ("Japonya saati kaç", "Japonya'da saat 21:00. Senden 6 saat ileride."),
        ("Auckland'da saat kaç", "Auckland'da saat 00:00, günlerden perşembe. Senden 9 saat ileride."),
        ("İstanbul ile Tokyo arasında kaç saat fark var", "Tokyo, İstanbul'dan 6 saat ileride. Orada saat 21:00."),
        ("Ankara'da saat kaç", "Ankara'da saat 15:00. Seninle aynı saatte."),
    ])
    func turkish(text: String, expected: String) throws {
        let query = try #require(WorldClockQuery.parse(text, language: .turkish))
        #expect(query.answer(now: now, userTimeZone: istanbul, language: .turkish) == expected)
    }

    @Test("answers English questions", arguments: [
        ("what time is it in Tokyo", "It's 9:00 PM in Tokyo, 6 hours ahead of you."),
        ("what's the time difference with New York", "New York is 7 hours behind you; it's 8:00 AM there."),
        ("London time", "It's 1:00 PM in London, 2 hours behind you."),
        ("what's the time in Sydney right now", "It's 10:00 PM in Sydney, 7 hours ahead of you."),
    ])
    func english(text: String, expected: String) throws {
        let query = try #require(WorldClockQuery.parse(text, language: .english))
        let answer = query.answer(now: now, userTimeZone: istanbul, language: .english)
        #expect(answer.replacingOccurrences(of: "\u{202F}", with: " ") == expected)
    }

    @Test("leaves other time questions alone", arguments: [
        "saat kaç", "yarın saat 3'te Londra toplantısı ekle", "Londra'ya uçuş kaç saat sürer", "İstanbul'da hava nasıl",
        "Tokyo'da ne yenir",
    ])
    func notWorldClock(text: String) {
        #expect(WorldClockQuery.parse(text, language: .turkish) == nil)
    }

    @Test("leaves other English questions alone", arguments: [
        "what time is it", "what time does the London flight leave", "set a timer for ten minutes", "weather in Paris",
    ])
    func notEnglishWorldClock(text: String) {
        #expect(WorldClockQuery.parse(text, language: .english) == nil)
    }

    @Test("every place has a known time zone")
    func timeZonesExist() {
        for place in WorldPlace.all {
            #expect(TimeZone(identifier: place.timeZoneIdentifier) != nil, "\(place.englishName)")
        }
    }
}
