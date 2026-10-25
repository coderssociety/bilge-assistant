import AsistanCore
import Foundation
import FoundationModels

/// "Her gece 21'de hava durumunu söyle": the command runs by itself at that time, as if it had been said. Taken by
/// rule ahead of the tool the command names, so "her sabah 8'de günün özetini oku" sets up a routine instead of
/// reading the summary now. The schedule is read back before anything is saved.
struct AddRoutineTool: RuleRoutedTool {
    let name = "addRoutine"
    let description = "Her gün ya da seçilen günlerde belirli bir saatte kendiliğinden çalışan bir rutin kurar ('her gece 21'de hava durumunu söyle')."
    let store: RoutineStore
    var language = AssistantLanguage.turkish

    @Generable
    struct Arguments {
        @Guide(description: "Kullanıcının isteği, olduğu gibi")
        var request: String
    }

    @MainActor
    func claims(_ command: String) -> Bool {
        RoutineRequest.parse(command, language: language) != nil
    }

    func arguments(fromCommand command: String) -> Arguments? {
        Arguments(request: command)
    }

    func makeCall(_ arguments: Arguments) async -> PreparedToolCall {
        guard let request = RoutineRequest.parse(arguments.request, language: language),
              let routine = Routine(days: request.days, hour: request.hour, minute: request.minute, command: request.command)
        else {
            return .unavailable(name, message: String(localized: "Rutinin günlerini, saatini ya da ne yapacağını anlayamadım."))
        }
        guard RoutineRequest.parse(routine.command, language: language) == nil else {
            return .unavailable(name, message: String(localized: "Bir rutinin komutu başka bir rutin olamaz."))
        }
        let schedule = RoutineSchedule.describe(days: routine.days, hour: routine.hour, minute: routine.minute, language: language)
        let question = String(localized: "\(schedule) “\(routine.command)” rutinini kurayım mı?")
        return PreparedToolCall(toolName: name, argumentsDescription: "routine", risk: .needsConfirmation,
                                confirmationQuestion: question.prefix(1).uppercased(with: language.locale) + question.dropFirst(),
                                execute: { await add(routine, schedule: schedule) })
    }

    func call(arguments: Arguments) async throws -> String {
        try await makeCall(arguments).execute()
    }

    private func add(_ routine: Routine, schedule: String) async -> String {
        do {
            try await MainActor.run { try store.add(routine) }
            return String(localized: "Tamam, rutin kuruldu: \(schedule) “\(routine.command)”.")
        } catch {
            return ToolReply.failure(error)
        }
    }
}

/// "Rutinlerim neler", "akşam rutinini sil", "hava durumu rutinini iptal et", "bütün rutinleri sil".
struct ManageRoutinesTool: RuleRoutedTool {
    let name = "manageRoutines"
    let description = "Kurulu rutinleri listeler ya da birini veya hepsini siler ('rutinlerim neler', 'akşam rutinini sil')."
    let store: RoutineStore
    var language = AssistantLanguage.turkish

    @Generable
    struct Arguments {
        @Guide(description: "Kullanıcının isteği, olduğu gibi")
        var request: String
    }

    @MainActor
    func claims(_ command: String) -> Bool {
        RoutineRequest.removal(command, language: language) != nil || RoutineRequest.asksForList(command, language: language)
    }

    func arguments(fromCommand command: String) -> Arguments? {
        Arguments(request: command)
    }

    func makeCall(_ arguments: Arguments) async -> PreparedToolCall {
        let routines = await MainActor.run { store.routines }
        guard !routines.isEmpty else { return reply(String(localized: "Kurulu rutin yok.")) }
        guard let removal = RoutineRequest.removal(arguments.request, language: language) else {
            return reply(routines.count == 1
                ? String(localized: "Bir rutin var: \(listed(routines)).")
                : String(localized: "\(routines.count) rutin var: \(listed(routines))."))
        }
        if removal.every {
            return PreparedToolCall(toolName: name, argumentsDescription: "all routines", risk: .needsConfirmation,
                                    confirmationQuestion: String(localized: "Kurulu \(routines.count) rutinin hepsini sileyim mi?"),
                                    execute: { await remove(routines) })
        }
        let picked = RoutineChoice.chosen(routines, name: removal.name)
        guard let routine = picked.first else {
            return reply(String(localized: "Öyle bir rutin bulamadım. Kurulu olanlar: \(listed(routines))."))
        }
        // Nothing named one of several: asking beats deleting the wrong one.
        guard picked.count == 1 else {
            return reply(String(localized: "Birden fazla rutin var: \(listed(picked)). Hangisini sileyim?"))
        }
        return PreparedToolCall(toolName: name, argumentsDescription: "one routine", risk: .safe, confirmationQuestion: nil,
                                execute: { await remove([routine]) })
    }

    func call(arguments: Arguments) async throws -> String {
        try await makeCall(arguments).execute()
    }

    private func reply(_ text: String) -> PreparedToolCall {
        PreparedToolCall(toolName: name, argumentsDescription: "", risk: .safe, confirmationQuestion: nil, execute: { text })
    }

    private func listed(_ routines: [Routine]) -> String {
        routines.map { RoutineSchedule.describe($0, language: language) }.joined(separator: "; ")
    }

    private func remove(_ routines: [Routine]) async -> String {
        do {
            let count = try await MainActor.run { try store.remove(Set(routines.map(\.id))) }
            guard count == 1, let routine = routines.first else { return String(localized: "\(count) rutin silindi.") }
            return String(localized: "Rutin silindi: \(RoutineSchedule.describe(routine, language: language)).")
        } catch {
            return ToolReply.failure(error)
        }
    }
}
