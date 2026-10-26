import AsistanCore
import Foundation
import FoundationModels

/// "Yarınki toplantıyı iptal et", "diş hekimi randevusunu cumaya al". The event is found before asking, so the
/// question names it and its time; when several fit, the user is told which and asked to say the day or time.
/// A repeating event changes only in the occurrence meant, unless "hepsini" is said.
struct ChangeEventTool: AssistantTool {
    let name = "changeCalendarEvent"
    let description = "Takvimdeki bir etkinliği iptal eder ya da başka bir gün veya saate taşır ('yarınki toplantıyı iptal et', 'dişçi randevusunu cumaya al')."
    let risk = ToolRisk.needsConfirmation
    private static let listedMatches = 4

    @Generable
    struct Arguments {
        @Guide(description: "Kullanıcının isteği, olduğu gibi")
        var request: String
    }

    /// The day, time and title words are read from the words themselves, never guessed by the model.
    func arguments(fromCommand command: String) -> Arguments? {
        Arguments(request: command)
    }

    func makeCall(_ arguments: Arguments) async -> PreparedToolCall {
        let now = Date.now
        guard let change = CalendarChange.parse(arguments.request, language: AppLanguage.current, now: now),
              let interval = change.searchInterval(now: now) else {
            return .unavailable(name, message: String(localized: "Hangi etkinliği iptal edeceğimi ya da taşıyacağımı anlayamadım."))
        }
        let matches: [CalendarEventCandidate]
        do {
            matches = change.matches(in: try await CalendarAccess.shared.changeableEvents(in: interval), now: now)
        } catch {
            return .unavailable(name, message: error.localizedDescription)
        }
        guard let event = matches.first else {
            return .unavailable(name, message: String(localized: "Takviminde buna uyan bir etkinlik bulamadım."))
        }
        guard matches.count == 1 else {
            let list = matches.prefix(Self.listedMatches).map { "\(Self.when($0)) \($0.title)" }.joined(separator: "; ")
            return .unavailable(name, message: String(localized: "Birden fazla etkinlik uyuyor: \(list). Hangisi olduğunu günüyle ya da saatiyle söyler misin?"))
        }
        let all = change.allOccurrences && event.isRecurring
        switch change.action {
        case .cancel:
            return prepared(event, question: Self.cancelQuestion(event, all: all)) {
                try await CalendarAccess.shared.removeEvent(event, allOccurrences: all)
                    ? String(localized: "'\(event.title)' takviminden silindi.") : nil
            }
        case .move:
            guard let start = change.newStart(for: event, now: now) else {
                return .unavailable(name, message: String(localized: "'\(event.title)' etkinliğini ne zamana taşıyacağımı anlayamadım."))
            }
            let newTime = event.isAllDay ? ScheduledMoment.describeDay(start) : ScheduledMoment.describe(start)
            return prepared(event, question: Self.moveQuestion(event, to: newTime, all: all)) {
                try await CalendarAccess.shared.moveEvent(event, to: start, allOccurrences: all)
                    ? String(localized: "'\(event.title)' taşındı: \(newTime).") : nil
            }
        }
    }

    func call(arguments: Arguments) async throws -> String {
        ToolReply.failure(String(localized: "Takvimde değişikliği yalnızca onayla yaparım."))
    }

    /// `change` returns the reply, or nil when the event was changed or removed in the meantime.
    private func prepared(_ event: CalendarEventCandidate, question: String,
                          change: @escaping @Sendable () async throws -> String?) -> PreparedToolCall {
        PreparedToolCall(toolName: name, argumentsDescription: "event: \(event.id) \(event.start)", risk: risk,
                         confirmationQuestion: question, execute: {
                             do {
                                 return try await change()
                                     ?? ToolReply.failure(String(localized: "Etkinlik bu arada değişmiş ya da silinmiş, bulamadım."))
                             } catch {
                                 return ToolReply.failure(error)
                             }
                         })
    }

    private static func when(_ event: CalendarEventCandidate) -> String {
        event.isAllDay ? ScheduledMoment.describeDay(event.start) : ScheduledMoment.describe(event.start)
    }

    private static func cancelQuestion(_ event: CalendarEventCandidate, all: Bool) -> String {
        let (title, when) = (event.title, when(event))
        if all { return String(localized: "'\(title)' etkinliğinin \(when) olan tekrarını ve sonraki tüm tekrarlarını sileyim mi?") }
        if event.isRecurring { return String(localized: "'\(title)' tekrarlanan bir etkinlik; yalnızca bu tekrarını, \(when), sileyim mi?") }
        return String(localized: "'\(title)' etkinliğini, \(when), takviminden sileyim mi?")
    }

    private static func moveQuestion(_ event: CalendarEventCandidate, to newTime: String, all: Bool) -> String {
        let question = String(localized: "'\(event.title)' etkinliğini taşıyayım mı? Şu an \(when(event)), yeni zamanı \(newTime).")
        guard event.isRecurring else { return question }
        return question + " " + (all ? String(localized: "Bu ve sonraki tüm tekrarlar taşınacak.")
            : String(localized: "Yalnızca bu tekrar taşınacak."))
    }
}
