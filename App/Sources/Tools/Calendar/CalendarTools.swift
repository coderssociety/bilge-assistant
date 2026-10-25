import AsistanCore
import Foundation
import FoundationModels

struct CalendarQueryTool: AssistantTool {
    let name = "readCalendar"
    let description = "Takvimdeki etkinlikleri okur: bugün, yarın, belirli bir gün, bu hafta, haftaya ya da bu ay."
    private static let maxEvents = 12

    @Generable
    enum Range {
        case today, tomorrow, thisWeek, nextWeek, thisMonth
    }

    @Generable
    struct Arguments {
        var range: Range
        @Guide(description: "Belirli bir gün soruluyorsa bugünden kaç gün sonra: cuma günü, 15 Kasım; yoksa boş bırak", .range(0...366))
        var dayOffset: Int?
    }

    /// The day or span said in the command wins over the model's choice.
    func refine(_ arguments: Arguments, command: String) -> Arguments {
        guard let period = CalendarPeriod.parse(command, language: AppLanguage.current, now: .now) else { return arguments }
        return switch period {
        case .day(offset: 0): Arguments(range: .today, dayOffset: nil)
        case .day(offset: 1): Arguments(range: .tomorrow, dayOffset: nil)
        case let .day(offset): Arguments(range: arguments.range, dayOffset: offset)
        case .thisWeek: Arguments(range: .thisWeek, dayOffset: nil)
        case .nextWeek: Arguments(range: .nextWeek, dayOffset: nil)
        case .thisMonth: Arguments(range: .thisMonth, dayOffset: nil)
        }
    }

    func call(arguments: Arguments) async throws -> String {
        let period = Self.period(for: arguments)
        guard let interval = period.interval(now: .now) else {
            return ToolReply.failure(String(localized: "Hangi günlere bakacağımı anlayamadım."))
        }
        let label = Self.label(for: period, start: interval.start)
        do {
            let events = try await CalendarAccess.shared.events(from: interval.start, to: interval.end)
            guard !events.isEmpty else { return String(localized: "\(label) takvimde etkinlik yok.") }
            let dayFormat = Self.dayFormat(for: period)
            let lines = events.prefix(Self.maxEvents).map { Self.describe($0, dayFormat: dayFormat) }
            var answer = String(localized: "\(label) \(events.count) etkinlik var: \(lines.joined(separator: "; "))")
            if events.count > Self.maxEvents {
                answer += String(localized: " Bunlardan başka \(events.count - Self.maxEvents) etkinlik daha var.")
            }
            return answer
        } catch {
            return ToolReply.failure(error)
        }
    }

    private static func period(for arguments: Arguments) -> CalendarPeriod {
        if let offset = arguments.dayOffset { return .day(offset: offset) }
        return switch arguments.range {
        case .today: .day(offset: 0)
        case .tomorrow: .day(offset: 1)
        case .thisWeek: .thisWeek
        case .nextWeek: .nextWeek
        case .thisMonth: .thisMonth
        }
    }

    private static func label(for period: CalendarPeriod, start: Date) -> String {
        switch period {
        case .day(offset: 0): String(localized: "Bugün")
        case .day(offset: 1): String(localized: "Yarın")
        case .day: String(localized: "\(start.formatted(.dateTime.day().month(.wide).weekday(.wide).locale(AppLanguage.locale))) günü")
        case .thisWeek: String(localized: "Önümüzdeki 7 günde")
        case .nextWeek: String(localized: "Haftaya")
        case .thisMonth: String(localized: "Bu ay")
        }
    }

    /// Over a week a weekday names the day; over a month it needs the date too.
    private static func dayFormat(for period: CalendarPeriod) -> Date.FormatStyle? {
        switch period {
        case .day: nil
        case .thisWeek, .nextWeek: .dateTime.weekday(.wide)
        case .thisMonth: .dateTime.day().month(.wide).weekday(.wide)
        }
    }

    private static func describe(_ event: CalendarEventSummary, dayFormat: Date.FormatStyle?) -> String {
        let locale = AppLanguage.locale
        let title = event.title
        if event.isAllDay {
            return dayFormat.map { String(localized: "\(event.start.formatted($0.locale(locale))) tüm gün: \(title)") }
                ?? String(localized: "tüm gün: \(title)")
        }
        let format = (dayFormat ?? .dateTime).hour().minute().locale(locale)
        return "\(event.start.formatted(format)) \(title)"
    }
}

struct RemindersQueryTool: AssistantTool {
    let name = "readReminders"
    let description = "Anımsatıcılar uygulamasındaki tamamlanmamış yapılacakları listeler (zamanlayıcı ve alarmlar değil)."
    private static let maxReminders = 10

    @Generable
    struct Arguments {}

    func emptyArguments() -> Arguments? { Arguments() }

    func call(arguments: Arguments) async throws -> String {
        do {
            let titles = try await CalendarAccess.shared.incompleteReminderTitles()
            guard !titles.isEmpty else { return String(localized: "Bekleyen anımsatıcı yok.") }
            return String(localized: "\(titles.count) anımsatıcı var: \(titles.prefix(Self.maxReminders).joined(separator: "; "))")
        } catch {
            return ToolReply.failure(error)
        }
    }
}
