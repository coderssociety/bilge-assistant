import AsistanCore
import Foundation
import FoundationModels

struct SetTimerTool: AssistantTool {
    let name = "setTimer"
    let description = "Zamanlayıcı ya da alarm kurar. Süre için 'minutes'/'seconds', belirli bir saat için 'hour'/'minute' kullan."
    let service: TimerService

    @Generable
    struct Arguments {
        @Guide(description: "Kaç dakika sonra (süre)", .range(0...1440))
        var minutes: Int?
        @Guide(description: "Kaç saniye sonra (süre)", .range(0...3600))
        var seconds: Int?
        @Guide(description: "Belirli saat, 24 saat biçiminde. 'sabah yedi' → 7, 'akşam altı' → 18", .range(0...23))
        var hour: Int?
        @Guide(description: "Belirli saatin dakikası. 'yedi buçuk' → 30", .range(0...59))
        var minute: Int?
        @Guide(description: "Bir-üç kelimeyle ne için olduğu, örn. 'çay'. Söylenmediyse boş bırak.")
        var label: String?
    }

    /// The model reliably picks this tool but sometimes garbles numbers ("20:00" → 19), so precise
    /// times and durations come from the text itself.
    func refine(_ arguments: Arguments, command: String) -> Arguments {
        guard let parsed = TimerPhraseParser.parse(command) else { return arguments }
        var refined = arguments
        if let hour = parsed.hour {
            refined.hour = hour
            refined.minute = parsed.minute
            refined.minutes = nil
            refined.seconds = nil
        } else if let duration = parsed.durationSeconds {
            refined.minutes = duration / 60
            refined.seconds = duration % 60
            refined.hour = nil
            refined.minute = nil
        }
        return refined
    }

    func call(arguments: Arguments) async throws -> String {
        guard let fireDate = TimerSchedule.fireDate(minutes: arguments.minutes, seconds: arguments.seconds,
                                                    hour: arguments.hour, minute: arguments.minute, now: .now)
        else { return ToolReply.failure("Süre ya da saat anlaşılamadı.") }
        let timer = await service.schedule(at: fireDate, label: TimerSchedule.cleanLabel(arguments.label))
        let time = timer.fireDate.formatted(.dateTime.hour().minute().locale(Locale(identifier: "tr_TR")))
        let day = Calendar.current.isDateInToday(timer.fireDate) ? "" : "yarın "
        return "Tamam, \(day)saat \(time) için kurdum."
    }
}

struct ManageTimersTool: AssistantTool {
    let name = "manageTimers"
    let description = "Bu uygulamada kurulu zamanlayıcı ve alarmları listeler, sayar ya da hepsini iptal eder."
    let service: TimerService

    @Generable
    enum Action {
        case list, cancelAll
    }

    @Generable
    struct Arguments {
        var action: Action
    }

    func call(arguments: Arguments) async throws -> String {
        switch arguments.action {
        case .list:
            let timers = await service.timers
            guard !timers.isEmpty else { return "Kurulu zamanlayıcı yok." }
            let locale = Locale(identifier: "tr_TR")
            let lines = timers.map { "\($0.fireDate.formatted(.dateTime.hour().minute().locale(locale)))\($0.label.map { " \($0)" } ?? "")" }
            return "Zamanlayıcılar: " + lines.joined(separator: "; ")
        case .cancelAll:
            let count = await service.cancelAll()
            return count == 0 ? "İptal edilecek zamanlayıcı yoktu." : "\(count) zamanlayıcı iptal edildi."
        }
    }
}
