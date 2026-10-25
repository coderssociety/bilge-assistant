import Foundation

/// Which earthquakes are announced without being asked: strong enough, close enough to the user's city and
/// fresh. Each is announced once, also when a second source reports it again under its own id.
public struct EarthquakeAlertLog: Sendable {
    public static let minimumMagnitude = 4.0
    public static let radiusKm = 150.0
    /// Older events are news by the time they would be read; this also keeps the first check after launch quiet.
    public static let maximumAge: TimeInterval = 15 * 60
    /// Two reports this close in time and place are the same event (AFAD and Kandilli, or a revision).
    private static let sameEventSeconds: TimeInterval = 120
    private static let sameEventKm = 50.0
    private static let remembered: TimeInterval = 60 * 60

    private var announced: [Earthquake] = []

    public init() {}

    /// The events to announce now, oldest first; they are remembered as announced.
    public mutating func newAlerts(in earthquakes: [Earthquake], home: GeoPoint, now: Date) -> [Earthquake] {
        announced.removeAll { now.timeIntervalSince($0.date) > Self.remembered }
        var fresh: [Earthquake] = []
        for quake in earthquakes.sorted(by: { $0.date < $1.date }) where Self.isWorthAlerting(quake, home: home, now: now) {
            guard !(announced + fresh).contains(where: { Self.isSameEvent($0, quake) }) else { continue }
            fresh.append(quake)
        }
        announced += fresh
        return fresh
    }

    static func isWorthAlerting(_ quake: Earthquake, home: GeoPoint, now: Date) -> Bool {
        let age = now.timeIntervalSince(quake.date)
        return quake.magnitude >= minimumMagnitude && age <= maximumAge && age >= -maximumAge
            && quake.location.kilometres(to: home) <= radiusKm
    }

    static func isSameEvent(_ first: Earthquake, _ second: Earthquake) -> Bool {
        first.id == second.id || (abs(first.date.timeIntervalSince(second.date)) <= sameEventSeconds
            && first.location.kilometres(to: second.location) <= sameEventKm)
    }
}

extension EarthquakeReport {
    /// "Deprem uyarısı: 3 dakika önce Menderes, İzmir merkezli 4,6 büyüklüğünde, İzmir merkezine 30 kilometre uzaklıkta…"
    public static func alert(_ quake: Earthquake, home: Place, now: Date, language: AssistantLanguage) -> String {
        let report = EarthquakeReport(query: EarthquakeQuery(nearUser: true), home: home, source: .afad, now: now,
                                      language: language)
        return (language == .english ? "Earthquake alert: " : "Deprem uyarısı: ") + report.describe(quake)
    }

    /// The notification's title: "Deprem: 4,6 · Menderes, İzmir".
    public static func alertTitle(_ quake: Earthquake, language: AssistantLanguage) -> String {
        let word = language == .english ? "Earthquake" : "Deprem"
        return "\(word): \(magnitude(quake.magnitude, language: language)) · \(quake.place)"
    }
}
