import Foundation

public enum TimerSchedule {
    public static let maxDuration: TimeInterval = 24 * 60 * 60
    public static let maxLabelLength = 40

    /// A clock time (hour, optional minute) takes precedence; a time already passed today means tomorrow.
    public static func fireDate(minutes: Int?, seconds: Int?, hour: Int?, minute: Int?,
                                now: Date, calendar: Calendar = .current) -> Date? {
        if let hour {
            let minute = minute ?? 0
            guard (0..<24).contains(hour), (0..<60).contains(minute),
                  let today = calendar.date(bySettingHour: hour, minute: minute, second: 0, of: now)
            else { return nil }
            return today > now ? today : calendar.date(byAdding: .day, value: 1, to: today)
        }
        let duration = TimeInterval((minutes ?? 0) * 60 + (seconds ?? 0))
        guard duration > 0, duration <= maxDuration else { return nil }
        return now.addingTimeInterval(duration)
    }

    public static func cleanLabel(_ label: String?) -> String? {
        guard let trimmed = label?.trimmingCharacters(in: .whitespacesAndNewlines), !trimmed.isEmpty else { return nil }
        guard trimmed.count > maxLabelLength else { return trimmed }
        let words = trimmed.prefix(maxLabelLength).split(separator: " ").dropLast()
        return words.isEmpty ? String(trimmed.prefix(maxLabelLength)) : words.joined(separator: " ")
    }
}
