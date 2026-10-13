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
        let locale = Locale(identifier: "tr_TR")
        let time = date.formatted(.dateTime.hour(.twoDigits(amPM: .omitted)).minute(.twoDigits).locale(locale))
        let day: String
        if calendar.isDateInToday(date) { day = "bugün" }
        else if calendar.isDateInTomorrow(date) { day = "yarın" }
        else { day = date.formatted(.dateTime.day().month(.wide).weekday(.wide).locale(locale)) }
        return "\(day) saat \(time)"
    }

    private static let partOfDayWords = ["sabah", "ogle", "aksam", "gece"]

    /// Day and clock time stated in the text override the model's values. A model hour is kept only
    /// when the text names a part of day ("yarın akşam"); otherwise it was invented, so it is dropped.
    static func refine(dayOffset: Int?, hour: Int?, minute: Int?, command: String) -> (dayOffset: Int?, hour: Int?, minute: Int?) {
        let day = RelativeDayParser.dayOffset(in: command, now: .now)
        if let clock = TimerPhraseParser.parse(command), let parsedHour = clock.hour {
            return (day, parsedHour, clock.minute)
        }
        let folded = TurkishText.folded(command)
        let mentionsPartOfDay = partOfDayWords.contains { folded.contains($0) }
        return mentionsPartOfDay ? (day, hour, minute) : (day, nil, nil)
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

    func refine(_ arguments: Arguments, command: String) -> Arguments {
        let moment = ScheduledMoment.refine(dayOffset: arguments.dayOffset, hour: arguments.hour,
                                            minute: arguments.minute, command: command)
        var refined = arguments
        (refined.dayOffset, refined.hour, refined.minute) = moment
        return refined
    }

    func confirmationQuestion(for arguments: Arguments) -> String {
        guard let start = ScheduledMoment.resolve(dayOffset: arguments.dayOffset, hour: arguments.hour, minute: arguments.minute)
        else { return "'\(arguments.title)' etkinliğini ekleyeyim mi?" }
        return "\(ScheduledMoment.describe(start).capitalizedFirst) için '\(arguments.title)' etkinliğini takvime ekleyeyim mi?"
    }

    func call(arguments: Arguments) async throws -> String {
        guard let start = ScheduledMoment.resolve(dayOffset: arguments.dayOffset, hour: arguments.hour, minute: arguments.minute)
        else { return ToolReply.failure("Etkinliğin günü ya da saati anlaşılamadı.") }
        let duration = TimeInterval((arguments.durationMinutes ?? Self.defaultDurationMinutes) * 60)
        do {
            try await CalendarAccess.shared.addEvent(title: arguments.title, start: start, end: start.addingTimeInterval(duration))
            return "Ekledim: \(ScheduledMoment.describe(start)), \(arguments.title)."
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
        else { return "'\(arguments.title)' anımsatıcısını ekleyeyim mi?" }
        return "'\(arguments.title)' anımsatıcısını \(ScheduledMoment.describe(due)) için ekleyeyim mi?"
    }

    func call(arguments: Arguments) async throws -> String {
        let due = ScheduledMoment.resolve(dayOffset: arguments.dayOffset, hour: arguments.hour, minute: arguments.minute)
        do {
            try await CalendarAccess.shared.addReminder(title: arguments.title, due: due)
            return due.map { "Ekledim, \(ScheduledMoment.describe($0)) hatırlatacağım." } ?? "'\(arguments.title)' anımsatıcılara eklendi."
        } catch {
            return ToolReply.failure(error)
        }
    }
}

extension String {
    var capitalizedFirst: String {
        guard let first else { return self }
        return String(first).uppercased(with: Locale(identifier: "tr_TR")) + dropFirst()
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
                return ToolReply.failure("Anımsatıcılarında '\(arguments.title)' diye tamamlanmamış bir iş bulamadım.")
            }
            return "'\(title)' tamamlandı olarak işaretlendi."
        } catch {
            return ToolReply.failure(error)
        }
    }
}
