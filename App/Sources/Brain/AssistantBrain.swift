import AsistanCore
import Foundation
import FoundationModels

/// The local "understand and act" layer on Apple's on-device model:
/// route the command, run the chosen tool and speak its result, or chat when no action fits.
@MainActor
final class AssistantBrain: CommandHandling {
    private static let maximumResponseTokens = 250

    private let model = SystemLanguageModel.default
    private let router: CommandRouter?
    private let routerError: String?
    private var conversation: LanguageModelSession?
    private var previousTurn: CommandRouter.PreviousTurn?
    /// Asks the user before `.needsConfirmation` tools run; without it those tools never run.
    weak var confirmer: (any ConfirmationProviding)?

    init(tools: [any AssistantTool]) {
        do {
            router = try CommandRouter(tools: tools, model: model)
            routerError = nil
        } catch {
            Log.brain.fault("Router schema failed: \(String(describing: error), privacy: .public)")
            router = nil
            routerError = "Komut yönlendirici başlatılamadı."
        }
    }

    /// A user-facing reason when the on-device model cannot be used, nil when it is ready.
    var unavailableReason: String? {
        if let routerError { return routerError }
        switch model.availability {
        case .available:
            return nil
        case let .unavailable(reason):
            return switch reason {
            case .deviceNotEligible: "Bu Mac, Apple'ın cihaz içi dil modelini desteklemiyor."
            case .appleIntelligenceNotEnabled: "Apple Intelligence kapalı. Sistem Ayarları'ndan açman gerekiyor."
            case .modelNotReady: "Dil modeli henüz hazır değil, sistem indiriyor olabilir."
            @unknown default: "Cihaz içi dil modeli şu an kullanılamıyor."
            }
        }
    }

    func prewarm() {
        guard unavailableReason == nil else { return }
        router?.prewarm()
        conversationSession().prewarm()
    }

    func respond(to command: String) -> AsyncThrowingStream<String, any Error> {
        AsyncThrowingStream { continuation in
            let task = Task { @MainActor in
                do {
                    try await handle(command, continuation: continuation)
                    continuation.finish()
                } catch is CancellationError {
                    continuation.finish(throwing: CancellationError())
                } catch {
                    Log.brain.error("Turn failed: \(String(describing: error), privacy: .public)")
                    continuation.yield(Self.spokenMessage(for: error))
                    continuation.finish()
                }
            }
            continuation.onTermination = { _ in task.cancel() }
        }
    }

    func endConversation() {
        conversation = nil
        previousTurn = nil
    }

    private func handle(_ command: String, continuation: AsyncThrowingStream<String, any Error>.Continuation) async throws {
        guard let router, unavailableReason == nil else {
            continuation.yield(unavailableReason ?? "Dil modeli kullanılamıyor.")
            return
        }
        switch try await router.route(command, previous: previousTurn) {
        case let .tool(call):
            let result = try await run(call, for: command, continuation: continuation)
            if call.answersWithLanguageModel, !ToolReply.isFailure(result) {
                let answer = try await answer(command, from: result, into: continuation)
                previousTurn = .init(command: command, action: call.toolName, result: answer)
            } else {
                previousTurn = .init(command: command, action: call.toolName, result: result)
                continuation.yield(ToolReply.spoken(result))
            }
        case .conversation:
            let reply = try await streamConversation(command, into: continuation)
            previousTurn = .init(command: command, action: CommandRouter.conversationAction, result: reply)
        }
    }

    /// Runs a prepared call, asking first when it is risky. Anything but a clear "yes" cancels.
    private func run(
        _ call: PreparedToolCall,
        for command: String,
        continuation: AsyncThrowingStream<String, any Error>.Continuation
    ) async throws -> String {
        if call.risk == .needsConfirmation {
            guard let confirmer, let question = call.confirmationQuestion else {
                await ActionAuditLog.shared.record(command: command, call: call, decision: .unconfirmed, result: nil)
                return "Bu işlem için onay gerekiyor ama şu an onay alamıyorum, bu yüzden yapmadım."
            }
            let answer = await confirmer.confirm(question)
            try Task.checkCancellation()
            guard answer == .confirmed else {
                let decision: ActionAuditLog.Decision = answer == .rejected ? .rejected : .unconfirmed
                await ActionAuditLog.shared.record(command: command, call: call, decision: decision, result: nil)
                return answer == .rejected ? "Tamam, yapmadım." : "Net bir onay duymadım, bu yüzden yapmadım."
            }
        }
        Log.tools.info("Running \(call.toolName, privacy: .public) \(call.argumentsDescription, privacy: .private)")
        let result = try await call.execute()
        await ActionAuditLog.shared.record(command: command, call: call, decision: .executed, result: result)
        return result
    }

    /// Answers about untrusted text (the screen) in a fresh session that has no tools.
    private func answer(
        _ command: String,
        from material: String,
        into continuation: AsyncThrowingStream<String, any Error>.Continuation
    ) async throws -> String {
        let session = LanguageModelSession(model: model, instructions: BrainInstructions.screen())
        let prompt = "Kullanıcının isteği: \(command)\n\nEkrandaki metin:\n<<<\n\(material)\n>>>"
        let options = GenerationOptions(temperature: 0.3, maximumResponseTokens: Self.maximumResponseTokens)
        var emitted = ""
        for try await snapshot in session.streamResponse(to: prompt, options: options) {
            let text = snapshot.content
            guard text.count > emitted.count, text.hasPrefix(emitted) else { continue }
            continuation.yield(String(text.dropFirst(emitted.count)))
            emitted = text
        }
        return emitted
    }

    private func streamConversation(
        _ command: String,
        into continuation: AsyncThrowingStream<String, any Error>.Continuation
    ) async throws -> String {
        let options = GenerationOptions(temperature: 0.6, maximumResponseTokens: Self.maximumResponseTokens)
        var emitted = ""
        do {
            for try await snapshot in conversationSession().streamResponse(to: command, options: options) {
                let text = snapshot.content
                guard text.count > emitted.count, text.hasPrefix(emitted) else { continue }
                continuation.yield(String(text.dropFirst(emitted.count)))
                emitted = text
            }
        } catch let error as LanguageModelError {
            guard case .contextSizeExceeded = error, emitted.isEmpty else { throw error }
            Log.brain.info("Conversation context full; starting fresh")
            conversation = nil
            return try await streamConversation(command, into: continuation)
        }
        return emitted
    }

    private func conversationSession() -> LanguageModelSession {
        if let conversation { return conversation }
        let created = LanguageModelSession(model: model, instructions: BrainInstructions.make())
        conversation = created
        return created
    }

    private static func spokenMessage(for error: any Error) -> String {
        guard let error = error as? LanguageModelError else {
            return "Üzgünüm, bir sorun oluştu. Tekrar dener misin?"
        }
        return switch error {
        case .guardrailViolation, .refusal: "Bu isteğe yardımcı olamıyorum."
        case .unsupportedLanguageOrLocale: "Dil modeli Türkçeyi şu an desteklemiyor. Apple Intelligence dilinin Türkçe olduğunu kontrol et."
        case .timeout: "Yanıt çok uzun sürdü. Tekrar dener misin?"
        default: "Üzgünüm, bunu yapamadım. Tekrar dener misin?"
        }
    }
}
