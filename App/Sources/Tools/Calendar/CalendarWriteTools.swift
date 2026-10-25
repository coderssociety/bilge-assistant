import AsistanCore
import Foundation
import FoundationModels

/// Shared date resolution for tools that write to Calendar/Reminders: the day and clock time come
/// from deterministic parsers when the text states them, the model's guesses only fill gaps.
enum ScheduledMoment {
    static func resolve(dayOffset: Int?, hour: Int?, minute: Int?, now: Date = .now) -> Date? {
        let calendar = Calendar.current
        guard let day = calendar.date(byAdding: .day, value: dayOffset ?? 0, to: calendar.startOfDay(for: now)) else {
            return nil
        }
        guard let hour else { return dayOffset == nil ? nil : calendar.date(bySettingHour: 9, minute: 0, second: 0, of: day) }
        return calendar.date(bySettingHour: hour, minute: minute ?? 0, second: 0, of: day)
    }

    static func describe(_ date: Date, now: Date = .now) -> String {
        let calendar = Calendar.current
        let locale = AppLanguage.locale
        let time = date.formatted(.dateTime.hour(.twoDigits(amPM: .omitted)).minute(.twoDigits).locale(locale))
        let day: String
        if calendar.isDateInToday(date) { day = String(localized: "bugün") }
        else if calendar.isDateInTomorrow(date) { day = String(localized: "yarın") }
        else { day = date.formatted(.dateTime.day().month(.wide).weekday(.wide).locale(locale)) }
        return String(localized: "\(day) saat \(time)")
    }

    static func refine(dayOffset: Int?, hour: Int?, minute: Int?, command: String) -> (dayOffset: Int?, hour: Int?, minute: Int?) {
        let moment = AppointmentTime.refine(.init(dayOffset: dayOffset, hour: hour, minute: minute), command: command,
                                            language: AppLanguage.current, now: .now)
        return (moment.dayOffset, moment.hour, moment.minute)
    }
}

struct CreateEventTool: AssistantTool {
    let name = "addCalendarEvent"
    let description = "Takvime yeni bir etkinlik ya da randevu ekler."
    let risk = ToolRisk.needsConfirmation
    private static let defaultDurationMinutes = 60

    @Generable
    struct Arguments {
        @Guide(description: "Etkinliğin kısa adı, örn. 'Diş hekimi'")
        var title: String
        @Guide(description: "Bugünden kaç gün sonra: bugün 0, yarın 1", .range(0...60))
        var dayOffset: Int?
        @Guide(description: "Başlangıç saati, 24 saat biçiminde", .range(0...23))
        var hour: Int?
        @Guide(description: "Başlangıç dakikası", .range(0...59))
        var minute: Int?
        @Guide(description: "Süre (dakika); söylenmediyse boş bırak", .range(5...720))
        var durationMinutes: Int?
    }

    /// The Turkish question starts with the date; the English one ("…for tomorrow at 10:00?") does not.
    private static func sentenceStart(_ text: String) -> String {
        AppLanguage.current == .english ? text : text.capitalizedFirst
    }

    func refine(_ arguments: Arguments, command: String) -> Arguments {
        let moment = ScheduledMoment.refine(dayOffset: arguments.dayOffset, hour: arguments.hour,
                                            minute: arguments.minute, command: command)
        var refined = arguments
        (refined.dayOffset, refined.hour, refined.minute) = moment
        return refined
    }

    func confirmationQuestion(for arguments: Arguments) -> String {
        guard let start = ScheduledMoment.resolve(dayOffset: arguments.dayOffset, hour: arguments.hour, minute: arguments.minute)
        else { return String(localized: "'\(arguments.title)' etkinliğini ekleyeyim mi?") }
        return String(
            localized: "\(Self.sentenceStart(ScheduledMoment.describe(start))) için '\(arguments.title)' etkinliğini takvime ekleyeyim mi?")
    }

    func call(arguments: Arguments) async throws -> String {
        guard let start = ScheduledMoment.resolve(dayOffset: arguments.dayOffset, hour: arguments.hour, minute: arguments.minute)
        else { return ToolReply.failure(String(localized: "Etkinliğin günü ya da saati anlaşılamadı.")) }
        let duration = TimeInterval((arguments.durationMinutes ?? Self.defaultDurationMinutes) * 60)
        do {
            try await CalendarAccess.shared.addEvent(title: arguments.title, start: start, end: start.addingTimeInterval(duration))
            return String(localized: "Ekledim: \(ScheduledMoment.describe(start)), \(arguments.title).")
        } catch {
            return ToolReply.failure(error)
        }
    }
}

struct CreateReminderTool: AssistantTool {
    let name = "addReminder"
    let description = "Anımsatıcılar uygulamasına yeni bir yapılacak ekler; istenirse belirli gün ve saatte hatırlatır."
    let risk = ToolRisk.needsConfirmation

    @Generable
    struct Arguments {
        @Guide(description: "Yapılacak iş, örn. 'Ekmek al'")
        var title: String
        @Guide(description: "Bugünden kaç gün sonra hatırlatılacak: bugün 0, yarın 1", .range(0...60))
        var dayOffset: Int?
        @Guide(description: "Hatırlatma saati, 24 saat biçiminde", .range(0...23))
        var hour: Int?
        @Guide(description: "Hatırlatma dakikası", .range(0...59))
        var minute: Int?
    }

    func refine(_ arguments: Arguments, command: String) -> Arguments {
        let moment = ScheduledMoment.refine(dayOffset: arguments.dayOffset, hour: arguments.hour,
                                            minute: arguments.minute, command: command)
        var refined = arguments
        (refined.dayOffset, refined.hour, refined.minute) = moment
        return refined
    }

    func confirmationQuestion(for arguments: Arguments) -> String {
        guard let due = ScheduledMoment.resolve(dayOffset: arguments.dayOffset, hour: arguments.hour, minute: arguments.minute)
        else { return String(localized: "'\(arguments.title)' anımsatıcısını ekleyeyim mi?") }
        return String(localized: "'\(arguments.title)' anımsatıcısını \(ScheduledMoment.describe(due)) için ekleyeyim mi?")
    }

    func call(arguments: Arguments) async throws -> String {
        let due = ScheduledMoment.resolve(dayOffset: arguments.dayOffset, hour: arguments.hour, minute: arguments.minute)
        do {
            try await CalendarAccess.shared.addReminder(title: arguments.title, due: due)
            return due.map { String(localized: "Ekledim, \(ScheduledMoment.describe($0)) hatırlatacağım.") }
                ?? String(localized: "'\(arguments.title)' anımsatıcılara eklendi.")
        } catch {
            return ToolReply.failure(error)
        }
    }
}

extension String {
    var capitalizedFirst: String {
        guard let first else { return self }
        return String(first).uppercased(with: AppLanguage.locale) + dropFirst()
    }
}

struct CompleteReminderTool: AssistantTool {
    let name = "completeReminder"
    let description = "Anımsatıcılardaki bir yapılacağı tamamlandı olarak işaretler ('faturayı ödedim, işaretle', 'ilacı aldım, listeden düş')."

    @Generable
    struct Arguments {
        @Guide(description: "Tamamlanan işin adı, örn. 'Süt al'")
        var title: String
    }

    /// The matcher finds "Süt al" in "süt almayı tamamladım işaretle" by itself. Extracting the title
    /// with the model also tripped Apple's guardrails on such sentences.
    func arguments(fromCommand command: String) -> Arguments? {
        Arguments(title: command)
    }

    func call(arguments: Arguments) async throws -> String {
        do {
            guard let title = try await CalendarAccess.shared.completeReminder(matching: arguments.title) else {
                return ToolReply.failure(String(localized: "Anımsatıcılarında '\(arguments.title)' diye tamamlanmamış bir iş bulamadım."))
            }
            return String(localized: "'\(title)' tamamlandı olarak işaretlendi.")
        } catch {
            return ToolReply.failure(error)
        }
    }
}
