import Foundation
import Testing
@testable import AsistanCore

@Suite("UpcomingAlerts")
struct UpcomingAlertsTests {
    private let now = Date(timeIntervalSince1970: 1_800_000_000)
    private let lead: TimeInterval = 10 * 60
    private let grace: TimeInterval = 5 * 60

    private func event(_ title: String, inMinutes minutes: Double) -> AlertCandidate {
        AlertCandidate(key: "e-\(title)", title: title, date: now.addingTimeInterval(minutes * 60), kind: .event)
    }

    private func reminder(_ title: String, inMinutes minutes: Double) -> AlertCandidate {
        AlertCandidate(key: "r-\(title)", title: title, date: now.addingTimeInterval(minutes * 60), kind: .reminder)
    }

    @Test("announces events starting within the lead time, not later ones or ones long started")
    func events() {
        let candidates = [event("Toplantı", inMinutes: 9), event("Akşam yemeği", inMinutes: 45), event("Sabah koşusu", inMinutes: -20)]
        let due = UpcomingAlerts.due(candidates, now: now, lead: lead, grace: grace, announced: [])
        #expect(due.map(\.title) == ["Toplantı"])
    }

    @Test("announces reminders whose time has come, within the grace period")
    func reminders() {
        let candidates = [reminder("İlaç", inMinutes: -1), reminder("Süt", inMinutes: 3), reminder("Eski", inMinutes: -30)]
        let due = UpcomingAlerts.due(candidates, now: now, lead: lead, grace: grace, announced: [])
        #expect(due.map(\.title) == ["İlaç"])
    }

    @Test("never announces the same item twice, sorted by time")
    func announcedOnce() {
        let candidates = [event("B", inMinutes: 8), event("A", inMinutes: 2)]
        let due = UpcomingAlerts.due(candidates, now: now, lead: lead, grace: grace, announced: ["e-B"])
        #expect(due.map(\.title) == ["A"])
    }

    @Test("speaks minutes until an event, or that it is starting")
    func messages() {
        #expect(UpcomingAlerts.message(for: [event("Toplantı", inMinutes: 9.2)], now: now) == "10 dakika sonra Toplantı var.")
        #expect(UpcomingAlerts.message(for: [event("Toplantı", inMinutes: 0.5)], now: now) == "Toplantı şimdi başlıyor.")
        #expect(UpcomingAlerts.message(for: [reminder("İlacını al", inMinutes: 0)], now: now) == "Hatırlatma: İlacını al.")
        #expect(UpcomingAlerts.message(for: [event("A", inMinutes: 5), reminder("B", inMinutes: 0)], now: now)
            == "5 dakika sonra A var. Hatırlatma: B.")
    }
}
