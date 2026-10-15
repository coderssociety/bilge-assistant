import AppKit
import AsistanCore
import FoundationModels

/// "Günün özeti", and the first "günaydın" of the day: weather, today's remaining events, reminders
/// due, unread mail. Parts are gathered at once and any that is slow or unavailable is left out.
struct BriefingTool: RuleRoutedTool {
    static let enabledKey = "morningBriefingEnabled"
    private static let lastBriefingKey = "lastMorningBriefing"
    private static let partTimeout: Duration = .seconds(5)
    /// "Günaydın" after noon is a greeting, not a request for the morning summary.
    private static let morningEndHour = 12

    let name = "dailyBriefing"
    let description = "Günün özetini söyler: hava durumu, bugünkü etkinlikler, anımsatıcılar ve okunmamış e-postalar."
    /// UserDefaults is not Sendable, so it is looked up where used rather than stored.
    private var defaults: UserDefaults { .standard }

    @Generable
    struct Arguments {}

    func emptyArguments() -> Arguments? { Arguments() }

    @MainActor
    func claims(_ command: String) -> Bool {
        if BriefingIntent.isRequest(command, language: AppLanguage.current) { return true }
        guard BriefingIntent.isMorningGreeting(command, language: AppLanguage.current), defaults.object(forKey: Self.enabledKey) as? Bool ?? true,
              Calendar.current.component(.hour, from: .now) < Self.morningEndHour else { return false }
        let last = defaults.object(forKey: Self.lastBriefingKey) as? Date
        return !(last.map { Calendar.current.isDateInToday($0) } ?? false)
    }

    func call(arguments: Arguments) async throws -> String {
        defaults.set(Date.now, forKey: Self.lastBriefingKey)
        let now = Date.now
        let endOfDay = Calendar.current.date(byAdding: .day, value: 1, to: Calendar.current.startOfDay(for: now)) ?? now
        async let weather = Self.bounded { try await Self.weather() }
        async let events = Self.bounded {
            try await CalendarAccess.shared.events(from: now, to: endOfDay)
                .filter { !$0.isAllDay }
                .map { DailyBriefing.Event(title: $0.title, start: $0.start) }
        }
        async let reminders = Self.bounded { try await CalendarAccess.shared.dueReminderTitles(until: endOfDay) }
        async let mail = Self.bounded { try await Self.unreadMail() }
        let briefing = DailyBriefing(now: now, weather: await weather ?? nil, events: await events ?? [],
                                     reminders: await reminders ?? [], unreadMail: await mail ?? nil)
        return briefing.text(language: AppLanguage.current)
    }

    private static func weather() async throws -> String? {
        let report = try await WeatherTool().call(arguments: .init(city: nil, dayOffset: 0))
        return ToolReply.isFailure(report) ? nil : report
    }

    /// Only when Mail is already open: the summary should not launch it.
    private static func unreadMail() async throws -> Int? {
        let isRunning = await MainActor.run {
            NSWorkspace.shared.runningApplications.contains { $0.bundleIdentifier == "com.apple.mail" }
        }
        guard isRunning else { return nil }
        return Int(try await AppleScriptRunner.run("tell application \"Mail\" to return unread count of inbox"))
    }

    /// The part's value, or nil if it failed or took longer than `partTimeout`.
    private static func bounded<T: Sendable>(_ part: @escaping @Sendable () async throws -> T) async -> T? {
        await withTaskGroup(of: T?.self) { group in
            group.addTask { try? await part() }
            group.addTask {
                try? await Task.sleep(for: partTimeout)
                return nil
            }
            let first = await group.next() ?? nil
            group.cancelAll()
            return first
        }
    }
}
