import AsistanCore
import Foundation
import FoundationModels

/// The local "understand and act" layer. Apple's on-device model routes every command and runs tools;
/// conversation and screen answers go to the LM Studio model when one is selected, else to Apple's.
@MainActor
final class AssistantBrain: CommandHandling {
    static let maximumResponseTokens = 250

    private let model = SystemLanguageModel.default
    private let router: CommandRouter?
    private let routerError: String?
    private var conversation: LanguageModelSession?
    /// The memory revision `conversation` was created with; a new fact means new instructions.
    private var conversationMemoryRevision = 0
    private var previousTurn: CommandRouter.PreviousTurn? {
        didSet { context.lastReply = previousTurn?.result }
    }
    private let context: ConversationContext
    private let memory: MemoryStore
    private let spreadsheet: SpreadsheetSession
    private let dictation: DictationSession
    private let tools: [any AssistantTool]
    private let localModel = LocalModelResponder()
    /// Asks the user before `.needsConfirmation` tools run; without it those tools never run.
    weak var confirmer: (any ConfirmationProviding)?

    init(tools: [any AssistantTool], context: ConversationContext = ConversationContext(),
         memory: MemoryStore = MemoryStore(fileURL: nil), spreadsheet: SpreadsheetSession = SpreadsheetSession(),
         dictation: DictationSession = DictationSession()) {
        self.context = context
        self.memory = memory
        self.spreadsheet = spreadsheet
        self.dictation = dictation
        self.tools = tools
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
        localModel.launched()
    }

    /// nil uses Apple's model for conversation.
    func useLocalModel(_ choice: LocalModelChoice?) {
        localModel.select(choice)
    }

    /// A catalog model finished downloading; if it is the selected one and kept loaded, load it now.
    func localModelDownloaded() {
        localModel.launched()
    }

    func setLocalModelKeepAlive(_ keepAlive: LocalModelKeepAlive) {
        localModel.keepAlive = keepAlive
    }

    func shutDownLocalModel() {
        localModel.shutDown()
    }

    func waitForLocalModel() async -> Bool {
        await localModel.waitUntilReady()
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

    /// Dictation takes everything said; Excel mode only spreadsheet commands. Either way the window
    /// stays open for the next input without the wake phrase.
    var workSession: ConversationFlow.WorkSession? {
        if dictation.isActive { return ConversationFlow.WorkSession(window: DictationSession.window) { _ in true } }
        guard spreadsheet.isActive else { return nil }
        return ConversationFlow.WorkSession(window: SpreadsheetSession.window) { command in
            SpreadsheetCommand.parse(TurkishNumberParser.digitize(command)) != nil || SpreadsheetCommand.mentionsCells(command)
        }
    }

    func respond(toWorkInput input: String) -> AsyncThrowingStream<String, any Error> {
        guard dictation.isActive else { return respond(to: input) }
        return AsyncThrowingStream { continuation in
            let task = Task { @MainActor in
                let reply = await dictation.handle(input)
                if !reply.isEmpty { continuation.yield(reply) }
                continuation.finish()
            }
            continuation.onTermination = { _ in task.cancel() }
        }
    }

    func endConversation() {
        dictation.end()
        spreadsheet.end()
        conversation = nil
        previousTurn = nil
        localModel.conversationEnded()
    }

    func conversationWillStart() {
        localModel.conversationWillStart()
    }

    private func handle(_ command: String, continuation: AsyncThrowingStream<String, any Error>.Continuation) async throws {
        guard let router, unavailableReason == nil else {
            continuation.yield(unavailableReason ?? "Dil modeli kullanılamıyor.")
            return
        }
        // "Bilge, dikteyi bitir" (end dictation) said with the wake phrase still controls dictation.
        if dictation.isActive, DictationCommand.parse(command) != nil {
            let reply = await dictation.handle(command)
            if !reply.isEmpty { continuation.yield(reply) }
            return
        }
        // "Bunu Ahmet'e gönder" (send this to Ahmet): what was on screen when the command was heard, read only when it points.
        context.screen = ContextIntent.points(command) ? await ScreenContextReader.snapshot() : nil
        if let parts = CompoundCommand.split(command) {
            try await handleCompound(command, parts: parts, router: router, continuation: continuation)
            return
        }
        try await handleSingle(command, router: router, continuation: continuation)
    }

    /// Parts that refer to an earlier result ("…bul ve ona mesaj at") are planned by the large model when
    /// one is selected. Independent parts, or all parts without that model, run one after another as
    /// separate commands, which is also several times faster.
    private func handleCompound(
        _ command: String,
        parts: [String],
        router: CommandRouter,
        continuation: AsyncThrowingStream<String, any Error>.Continuation
    ) async throws {
        if localModel.isEnabled, CompoundCommand.hasDependentParts(parts) {
            continuation.yield("Tamam, sırayla yapıyorum. ")
            do {
                let outcome = try await multiStepAgent(for: command, continuation: continuation).run(command)
                previousTurn = .init(command: command, action: "multiStep",
                                     result: outcome.readUntrustedContent ? nil : outcome.summary)
                context.lastReply = outcome.summary
                continuation.yield(outcome.summary)
                return
            } catch {
                try Self.rethrowIfCancelled(error)
            }
        }
        for part in parts {
            try Task.checkCancellation()
            try await handleSingle(part, router: router, continuation: continuation)
            continuation.yield(" ")
        }
    }

    private func multiStepAgent(
        for command: String,
        continuation: AsyncThrowingStream<String, any Error>.Continuation
    ) -> MultiStepAgent {
        MultiStepAgent(
            tools: tools,
            memory: memory.promptLines,
            complete: { [localModel] messages in
                try await localModel.complete(messages, maxTokens: MultiStepAgent.maxReplyTokens, announcingWaitTo: continuation)
            },
            execute: { [weak self] call in
                guard let self else { throw CancellationError() }
                return try await run(call, for: command, continuation: continuation)
            })
    }

    private func handleSingle(
        _ command: String,
        router: CommandRouter,
        continuation: AsyncThrowingStream<String, any Error>.Continuation
    ) async throws {
        switch try await router.route(command, previous: previousTurn) {
        case let .tool(call):
            if !call.answersWithLanguageModel { localModel.turnNeededNoModel() }
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
            let answer = await confirmer.confirm(question, strict: call.requiresExplicitYes)
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
        let prompt = "Kullanıcının isteği: \(command)\n\nMetin:\n<<<\n\(material)\n>>>"
        if localModel.isEnabled {
            do {
                return try await localModel.answer(prompt, instructions: BrainInstructions.material(), into: continuation)
            } catch {
                try Self.rethrowIfCancelled(error)
            }
        }
        let session = LanguageModelSession(model: model, instructions: BrainInstructions.material())
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
        if localModel.isEnabled {
            do {
                return try await localModel.converse(command, instructions: conversationInstructions(), into: continuation)
            } catch {
                try Self.rethrowIfCancelled(error)
            }
        }
        return try await streamAppleConversation(command, into: continuation)
    }

    private func streamAppleConversation(
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
            return try await streamAppleConversation(command, into: continuation)
        }
        return emitted
    }

    private func conversationSession() -> LanguageModelSession {
        if let conversation, conversationMemoryRevision == memory.revision { return conversation }
        let created = LanguageModelSession(model: model, instructions: conversationInstructions())
        conversation = created
        conversationMemoryRevision = memory.revision
        return created
    }

    private func conversationInstructions() -> String {
        BrainInstructions.make(memory: memory.promptLines)
    }

    /// A local-model failure falls back to Apple's model for this turn; cancellation must not.
    private static func rethrowIfCancelled(_ error: any Error) throws {
        if error is CancellationError || Task.isCancelled { throw CancellationError() }
        Log.brain.error("Local model unavailable, using Apple's: \(String(describing: error), privacy: .public)")
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
