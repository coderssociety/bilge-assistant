import Foundation
import Testing
@testable import AsistanCore

@Suite("Earthquake alerts")
struct EarthquakeAlertTests {
    private let now = ISO8601DateFormatter().date(from: "2026-10-25T16:00:00Z")!

    private func quake(_ id: String, magnitude: Double, minutesAgo: Double, latitude: Double = 38.4, longitude: Double = 27.1) -> Earthquake {
        Earthquake(id: id, date: now.addingTimeInterval(-minutesAgo * 60), magnitude: magnitude, depthKm: 10,
                   location: GeoPoint(latitude: latitude, longitude: longitude), place: "Yer", province: nil)
    }

    @Test("alerts: strong, near and fresh only")
    func alertThreshold() {
        let home = GeoPoint(latitude: 38.42, longitude: 27.14)
        var log = EarthquakeAlertLog()
        let alerts = log.newAlerts(in: [
            quake("weak", magnitude: 3.9, minutesAgo: 2),
            quake("old", magnitude: 5.0, minutesAgo: 20),
            quake("far", magnitude: 5.0, minutesAgo: 2, latitude: 39.93, longitude: 32.86),
            quake("near", magnitude: 4.0, minutesAgo: 3, latitude: 39.5, longitude: 27.5),
        ], home: home, now: now)
        #expect(alerts.map(\.id) == ["near"])
    }

    @Test("alerts: once per event, also when another source reports it")
    func alertDedupe() {
        let home = GeoPoint(latitude: 38.42, longitude: 27.14)
        var log = EarthquakeAlertLog()
        #expect(log.newAlerts(in: [quake("afad-1", magnitude: 4.5, minutesAgo: 2)], home: home, now: now).count == 1)
        #expect(log.newAlerts(in: [quake("afad-1", magnitude: 4.7, minutesAgo: 2)], home: home, now: now).isEmpty)
        let kandilli = quake("kandilli-1", magnitude: 4.4, minutesAgo: 1.5, latitude: 38.45, longitude: 27.2)
        #expect(log.newAlerts(in: [kandilli], home: home, now: now).isEmpty)
        #expect(log.newAlerts(in: [quake("afad-2", magnitude: 4.1, minutesAgo: 1, latitude: 39.1)], home: home, now: now).count == 1)
    }

    @Test("an alert sentence")
    func alertText() {
        let home = EarthquakeReport.Place(name: "İzmir", centre: GeoPoint(latitude: 38.42, longitude: 27.14))
        let text = EarthquakeReport.alert(quake("a", magnitude: 4.6, minutesAgo: 3), home: home, now: now, language: .turkish)
        #expect(text == "Deprem uyarısı: 3 dakika önce Yer merkezli 4,6 büyüklüğünde, İzmir merkezine 4 kilometre uzaklıkta, derinlik 10 kilometre.")
    }
}
