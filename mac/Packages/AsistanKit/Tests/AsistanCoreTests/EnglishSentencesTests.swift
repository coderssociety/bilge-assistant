import Foundation
import Testing
@testable import AsistanCore

@Suite("English spoken sentences")
struct EnglishSentencesTests {
    private var calendar: Calendar {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "Europe/Istanbul")!
        return calendar
    }

    private func date(_ hour: Int, _ minute: Int = 0) -> Date {
        calendar.date(from: DateComponents(year: 2026, month: 10, day: 15, hour: hour, minute: minute))!
    }

    @Test("weather")
    func weather() {
        #expect(WeatherReport.current(city: "London", temperature: 12.4, code: 3, language: .english)
            == "In London it's overcast right now, 12 degrees.")
        #expect(WeatherReport.daily(city: "Paris", dayName: "tomorrow", minimum: 8, maximum: 15.6, code: 61, rainChance: 40,
                                    language: .english)
            == "In Paris tomorrow it will be lightly rainy, between 8 and 16 degrees. There's a 40 percent chance of rain.")
        #expect(WeatherReport.current(city: "İzmir", temperature: 20, code: 0) == "İzmir'de şu an hava açık, 20 derece.")
    }

    @Test("daily briefing")
    func briefing() {
        let briefing = DailyBriefing(now: date(8), weather: "In London it's clear right now, 10 degrees.",
                                     events: [.init(title: "Standup", start: date(9, 30)), .init(title: "Lunch", start: date(13))],
                                     reminders: ["Buy milk"], unreadMail: 1)
        let text = briefing.text(calendar: calendar, language: .english)
        #expect(text.hasPrefix("Good morning. Today is Thursday, October 15."))
        #expect(text.contains("You have 2 events today: Standup at 9:30\u{202F}AM and Lunch at 1:00\u{202F}PM."))
        #expect(text.contains("Today's reminder: Buy milk."))
        #expect(text.hasSuffix("You have 1 unread email."))
    }

    @Test("briefing requests and the morning greeting")
    func briefingIntent() {
        #expect(BriefingIntent.isRequest("What does my day look like?", language: .english))
        #expect(BriefingIntent.isRequest("Give me my daily briefing", language: .english))
        #expect(!BriefingIntent.isRequest("What time is it", language: .english))
        #expect(BriefingIntent.isMorningGreeting("Bilge, good morning", language: .english))
        #expect(!BriefingIntent.isMorningGreeting("Good morning, what time is it", language: .english))
    }

    @Test("upcoming alerts")
    func alerts() {
        let now = date(9)
        let alerts = [
            AlertCandidate(key: "a", title: "Standup", date: date(9, 10), kind: .event),
            AlertCandidate(key: "b", title: "Call mom", date: date(9), kind: .reminder),
        ]
        #expect(UpcomingAlerts.message(for: alerts, now: now, language: .english)
            == "Standup starts in 10 minutes. Reminder: Call mom.")
    }
}
