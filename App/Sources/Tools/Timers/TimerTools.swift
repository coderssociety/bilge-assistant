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
        let parsed = AppLanguage.current == .english
            ? EnglishTimeParser.parse(command, appointment: false) : TimerPhraseParser.parse(command)
        guard let parsed else { return arguments }
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
        else { return ToolReply.failure(String(localized: "Süre ya da saat anlaşılamadı.")) }
        let timer = await service.schedule(at: fireDate, label: TimerSchedule.cleanLabel(arguments.label))
        let time = timer.fireDate.formatted(.dateTime.hour().minute().locale(AppLanguage.locale))
        return Calendar.current.isDateInToday(timer.fireDate)
            ? String(localized: "Tamam, saat \(time) için kurdum.")
            : String(localized: "Tamam, yarın saat \(time) için kurdum.")
    }
}

struct ManageTimersTool: AssistantTool {
    let name = "manageTimers"
    let description = "Bu uygulamada kurulu zamanlayıcı ve alarmları kalan süreleriyle listeler, birini ya da hepsini iptal eder."
    let service: TimerService

    @Generable
    enum Action {
        case list, cancel, cancelAll
    }

    @Generable
    struct Arguments {
        @Guide(description: "cancel tek bir zamanlayıcı için; cancelAll yalnızca 'hepsini/bütün' denince")
        var action: Action
        @Guide(description: "cancel için zamanlayıcının adı, örn. 'çay zamanlayıcısını' → 'çay'. Söylenmediyse boş bırak.")
        var label: String?
        @Guide(description: "cancel için sırası: 'ikinci' → 2, 'son' → -1. Söylenmediyse boş bırak.")
        var position: Int?
    }

    /// The model sometimes chose cancelAll for "çay zamanlayıcısını iptal et"; the words decide instead,
    /// and a request that cancels nothing only lists.
    func refine(_ arguments: Arguments, command: String) -> Arguments {
        guard arguments.action != .list else { return arguments }
        var refined = arguments
        switch TimerTarget.parse(command, language: AppLanguage.current) {
        case nil:
            refined.action = .list
        case .all:
            refined = Arguments(action: .cancelAll, label: nil, position: nil)
        case let .label(label):
            refined = Arguments(action: .cancel, label: label, position: nil)
        case let .position(position):
            refined = Arguments(action: .cancel, label: nil, position: position)
        case .any:
            refined.action = .cancel
        }
        return refined
    }

    func call(arguments: Arguments) async throws -> String {
        let timers = await service.timers
        switch arguments.action {
        case .list:
            guard !timers.isEmpty else { return String(localized: "Kurulu zamanlayıcı yok.") }
            return String(localized: "Zamanlayıcılar: ") + Self.describe(timers)
        case .cancel:
            let target: TimerTarget = if let label = TimerSchedule.cleanLabel(arguments.label) {
                .label(label)
            } else if let position = arguments.position, position != 0 {
                .position(position)
            } else {
                .any
            }
            switch TimerTarget.select(target, labels: timers.map(\.label)) {
            case let .timer(index):
                let timer = timers[index]
                guard await service.cancel(timer.id) else { return String(localized: "Bu zamanlayıcı az önce doldu.") }
                return timer.label.map { String(localized: "\($0) zamanlayıcısı iptal edildi.") }
                    ?? String(localized: "Saat \(Self.clock(timer.fireDate)) zamanlayıcısı iptal edildi.")
            case .noMatch:
                guard !timers.isEmpty else { return String(localized: "Kurulu zamanlayıcı yok.") }
                return String(localized: "Böyle bir zamanlayıcı bulamadım. ") + Self.describe(timers)
            case .ambiguous:
                return String(localized: "Hangisini iptal edeyim? ") + Self.describe(timers)
            }
        case .cancelAll:
            let count = await service.cancelAll()
            return count == 0
                ? String(localized: "İptal edilecek zamanlayıcı yoktu.")
                : String(localized: "\(count) zamanlayıcı iptal edildi.")
        }
    }

    private static func describe(_ timers: [TimerService.ScheduledTimer]) -> String {
        let now = Date.now
        return timers.map { timer in
            let left = Duration.seconds(TimerSchedule.spokenRemaining(until: timer.fireDate, now: now)).spoken
            let time = clock(timer.fireDate)
            return timer.label.map { String(localized: "\($0), saat \(time), \(left) kaldı") }
                ?? String(localized: "saat \(time), \(left) kaldı")
        }.joined(separator: "; ")
    }

    private static func clock(_ date: Date) -> String {
        date.formatted(.dateTime.hour().minute().locale(AppLanguage.locale))
    }
}
