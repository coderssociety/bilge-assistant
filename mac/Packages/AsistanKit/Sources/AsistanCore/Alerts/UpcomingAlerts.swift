import Foundation

public struct AlertCandidate: Equatable, Sendable {
    public enum Kind: Sendable {
        case event, reminder
    }

    /// Identifies the item at this time, so a rescheduled event is announced again.
    public let key: String
    public let title: String
    public let date: Date
    public let kind: Kind

    public init(key: String, title: String, date: Date, kind: Kind) {
        self.key = key
        self.title = title
        self.date = date
        self.kind = kind
    }
}

/// Decides what the assistant says without being asked: calendar events shortly before they start,
/// reminders when their time comes.
public enum UpcomingAlerts {
    /// An event that started this recently still counts as "starting now".
    private static let startedTolerance: TimeInterval = 60

    public static func due(
        _ candidates: [AlertCandidate], now: Date, lead: TimeInterval, grace: TimeInterval, announced: Set<String>
    ) -> [AlertCandidate] {
        candidates
            .filter { !announced.contains($0.key) }
            .filter { candidate in
                let offset = candidate.date.timeIntervalSince(now)
                return switch candidate.kind {
                case .event: offset >= -startedTolerance && offset <= lead
                case .reminder: offset <= 0 && offset >= -grace
                }
            }
            .sorted { $0.date < $1.date }
    }

    public static func message(for alerts: [AlertCandidate], now: Date, language: AssistantLanguage = .turkish) -> String {
        alerts.map { alert in
            let minutes = Int((alert.date.timeIntervalSince(now) / 60).rounded(.up))
            if language == .english {
                switch alert.kind {
                case .reminder: return "Reminder: \(alert.title)."
                case .event: return minutes <= 1 ? "\(alert.title) is starting now." : "\(alert.title) starts in \(minutes) minutes."
                }
            }
            switch alert.kind {
            case .reminder:
                return "Hatırlatma: \(alert.title)."
            case .event:
                return minutes <= 1 ? "\(alert.title) şimdi başlıyor." : "\(minutes) dakika sonra \(alert.title) var."
            }
        }.joined(separator: " ")
    }
}
