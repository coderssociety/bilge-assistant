import AsistanCore
import Foundation
import FoundationModels

struct CalendarQueryTool: AssistantTool {
    let name = "readCalendar"
    let description = "Takvimdeki etkinlikleri okur: bugün, yarın ya da bu hafta."
    let readingLayout: ContinuedReading.Layout? = .list(separator: "; ", perPart: 12)

    @Generable
    enum Range {
        case today, tomorrow, thisWeek
    }

    @Generable
    struct Arguments {
        var range: Range
    }

    func call(arguments: Arguments) async throws -> String {
        let calendar = Calendar.current
        let startOfToday = calendar.startOfDay(for: .now)
        let (start, days, label): (Date, Int, String) = switch arguments.range {
        case .today: (startOfToday, 1, String(localized: "Bugün"))
        case .tomorrow: (calendar.date(byAdding: .day, value: 1, to: startOfToday)!, 1, String(localized: "Yarın"))
        case .thisWeek: (startOfToday, 7, String(localized: "Önümüzdeki 7 günde"))
        }
        let end = calendar.date(byAdding: .day, value: days, to: start)!
        do {
            let events = try await CalendarAccess.shared.events(from: start, to: end)
            guard !events.isEmpty else { return String(localized: "\(label) takvimde etkinlik yok.") }
            let lines = events.map { Self.describe($0, includeDay: days > 1) }
            return String(localized: "\(label) \(events.count) etkinlik var: \(lines.joined(separator: "; "))")
        } catch {
            return ToolReply.failure(error)
        }
    }

    private static func describe(_ event: CalendarEventSummary, includeDay: Bool) -> String {
        let locale = AppLanguage.locale
        let title = event.title
        if event.isAllDay {
            return includeDay
                ? String(localized: "\(event.start.formatted(.dateTime.weekday(.wide).locale(locale))) tüm gün: \(title)")
                : String(localized: "tüm gün: \(title)")
        }
        let format: Date.FormatStyle = includeDay
            ? .dateTime.weekday(.wide).hour().minute().locale(locale)
            : .dateTime.hour().minute().locale(locale)
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
