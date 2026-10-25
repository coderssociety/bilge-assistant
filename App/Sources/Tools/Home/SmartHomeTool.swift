import AsistanCore
import Foundation
import FoundationModels

/// "Salonun ışığını aç", "klimayı 22 dereceye ayarla", "kapı kilitli mi": the command goes to Home Assistant as said,
/// which matches it to the user's devices in its own language, and its answer is spoken. Taken by rule only once Home
/// Assistant is set up and the command names a home device or room. Unlocking, the garage door and the alarm need an
/// explicit yes first.
struct SmartHomeTool: RuleRoutedTool {
    let name = "smartHome"
    let description = "Akıllı ev cihazlarını Home Assistant üzerinden yönetir ve durumlarını sorar: ışık, klima, priz, perde, kapı kilidi, termostat, garaj."
    let home: HomeAssistantConfig
    var language = AssistantLanguage.turkish

    @Generable
    struct Arguments {
        @Guide(description: "Kullanıcının komutu, olduğu gibi")
        var command: String
    }

    @MainActor
    func claims(_ command: String) -> Bool {
        home.isConfigured && HomeCommand.namesHomeDevice(command, language: language)
    }

    func arguments(fromCommand command: String) -> Arguments? {
        Arguments(command: command)
    }

    /// Home Assistant understands the user's own words better than the model's paraphrase of them.
    func refine(_ arguments: Arguments, command: String) -> Arguments {
        HomeCommand.namesHomeDevice(command, language: language) ? Arguments(command: command) : arguments
    }

    func makeCall(_ arguments: Arguments) async -> PreparedToolCall {
        let said = arguments.command.trimmingCharacters(in: .whitespacesAndNewlines)
        let guardsTheHouse = HomeCommand.guardsTheHouse(said, language: language)
        return PreparedToolCall(toolName: name, argumentsDescription: said, risk: guardsTheHouse ? .needsConfirmation : .safe,
                                confirmationQuestion: guardsTheHouse ? String(localized: "Home Assistant'a “\(said)” diyeyim mi?") : nil,
                                requiresExplicitYes: guardsTheHouse,
                                execute: { await send(said) })
    }

    func call(arguments: Arguments) async throws -> String {
        let call = await makeCall(arguments)
        guard call.risk == .safe else {
            return ToolReply.failure(String(localized: "Kilit, garaj kapısı ve alarm yalnızca onayla değiştirilir."))
        }
        return try await call.execute()
    }

    private func send(_ said: String) async -> String {
        guard !said.isEmpty else { return ToolReply.failure(HomeAssistantError.unexpected) }
        do {
            let connection = try await MainActor.run { try home.connection() }
            let reply = try await HomeAssistantClient.process(said, language: language, on: connection)
            return reply ?? String(localized: "Tamam.")
        } catch {
            Log.tools.error("Home Assistant request failed: \(String(describing: error), privacy: .public)")
            return ToolReply.failure(error)
        }
    }
}
