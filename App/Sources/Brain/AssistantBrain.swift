import AsistanCore
import Foundation
import FoundationModels

/// The local "understand and act" layer. Apple's on-device model routes every command and runs tools;
/// conversation and screen answers go to the LM Studio model when one is selected, else to Apple's.
@MainActor
final class AssistantBrain: CommandHandling {
    static let maximumResponseTokens = 250
    private static let continueReadingAction = "continueReading"
    private static let followUpMaterialLimit = 6000
    private static var moreToRead: String { " " + String(localized: "Devamı var; istersen “devam et” de.") }

    private let model = SystemLanguageModel.default
    private let router: CommandRouter?
    private let routerError: String?
    private var conversation: LanguageModelSession?
    /// The memory revision `conversation` was created with; a new fact means new instructions.
    private var conversationMemoryRevision = 0
    private var previousTurn: CommandRouter.PreviousTurn? {
        // "Bunu kopyala" and "bunu hatırla" take what was said, never a failed tool's raw result.
        didSet { context.lastReply = previousTurn?.result.flatMap { ToolReply.isFailure($0) ? nil : $0 } }
    }
    private let context: ConversationContext
    private let memory: MemoryStore
    private let spreadsheet: SpreadsheetSession
    private let dictation: DictationSession
    let interpreter: InterpreterSession
    let meetings: MeetingRecorder
    let whisper: WhisperProvider
    private let tools: [any AssistantTool]
    let language: AssistantLanguage
    private let localModel = LocalModelResponder()
    /// Asks the user before `.needsConfirmation` tools run; without it those tools never run.
    weak var confirmer: (any ConfirmationProviding)?

    init(tools: [any AssistantTool], context: ConversationContext = ConversationContext(),
         memory: MemoryStore = MemoryStore(fileURL: nil), spreadsheet: SpreadsheetSession = SpreadsheetSession(),
         dictation: DictationSession = DictationSession(), interpreter: InterpreterSession = InterpreterSession(),
         meetings: MeetingRecorder = MeetingRecorder(), whisper: WhisperProvider? = nil,
         language: AssistantLanguage = .turkish) {
        self.language = language
        self.context = context
        self.memory = memory
        self.spreadsheet = spreadsheet
        self.dictation = dictation
        self.interpreter = interpreter
        self.meetings = meetings
        self.whisper = whisper ?? WhisperProvider(language: language)
        self.tools = tools
        do {
            router = try CommandRouter(tools: tools, language: language, model: model)
            routerError = nil
        } catch {
            Log.brain.fault("Router schema failed: \(String(describing: error), privacy: .public)")
            router = nil
            routerError = String(localized: "Komut yönlendirici başlatılamadı.")
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
            case .deviceNotEligible: String(localized: "Bu Mac, Apple'ın cihaz içi dil modelini desteklemiyor.")
            case .appleIntelligenceNotEnabled: String(localized: "Apple Intelligence kapalı. Sistem Ayarları'ndan açman gerekiyor.")
            case .modelNotReady: String(localized: "Dil modeli henüz hazır değil, sistem indiriyor olabilir.")
            @unknown default: String(localized: "Cihaz içi dil modeli şu an kullanılamıyor.")
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
        respond(to: command, unattended: false)
    }

    /// A routine's command, run with nobody there to answer: a step that would need a yes is not taken, and the
    /// reply says the routine needs the user instead.
    func respondUnattended(to command: String) -> AsyncThrowingStream<String, any Error> {
        respond(to: command, unattended: true)
    }

    private func respond(to command: String, unattended: Bool) -> AsyncThrowingStream<String, any Error> {
        AsyncThrowingStream { continuation in
            let task = Task { @MainActor in
                do {
                    try await handle(command, unattended: unattended, continuation: continuation)
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
    /// stays open for the next input without the wake phrase. Interpreting takes even the wake phrase, in
    /// either of its languages.
    var workSession: ConversationFlow.WorkSession? {
        if let pair = interpreter.pair {
            return ConversationFlow.WorkSession(window: InterpreterSession.window, takesEverything: true,
                                                languages: pair.codes) { _ in true }
        }
        if dictation.isActive { return ConversationFlow.WorkSession(window: DictationSession.window) { _ in true } }
        guard spreadsheet.isActive else { return nil }
        let language = language
        return ConversationFlow.WorkSession(window: SpreadsheetSession.window) { command in
            SpreadsheetTool.command(in: command) != nil || SpreadsheetCommand.mentionsCells(command, language: language)
        }
    }

    func respond(toWorkInput input: String, language heard: String?) -> AsyncThrowingStream<String, any Error> {
        if interpreter.isActive { return interpret(input, heard: heard) }
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

    /// An interpreted utterance is spoken in the pair's other language; "Almancaya tercüme et" starting the
    /// interpreter is answered in the assistant's own.
    func replyLanguageCode(for input: String, isWorkInput: Bool, heard: String?) -> String? {
        if isWorkInput {
            guard interpreter.isActive, !InterpreterCommand.isStop(input) else { return nil }
            return interpreter.direction(heard: heard, assistant: language)?.target.code
        }
        if InterpreterCommand.start(in: input, language: language) != nil || MeetingCommand.parse(input, language: language) != nil {
            return nil
        }
        return TranslationRequest.target(in: input)?.code
    }

    func endConversation() {
        if interpreter.isActive {
            interpreter.end()
            if !meetings.isRecording { whisper.releaseUnlessListening() }
        }
        dictation.end()
        spreadsheet.end()
        conversation = nil
        previousTurn = nil
        localModel.conversationEnded()
    }

    func conversationWillStart() {
        localModel.conversationWillStart()
    }

    private func handle(
        _ command: String,
        unattended: Bool,
        continuation: AsyncThrowingStream<String, any Error>.Continuation
    ) async throws {
        // Interpreting and recording listen to the room; a routine must not start them with nobody there.
        if unattended, startsSession(command) {
            continuation.yield(Self.needsUser(command))
            return
        }
        // Before the model check: ending a recording must work, and save the transcript, even without a model.
        if try await handleSessionCommand(command, continuation: continuation) { return }
        guard let router, unavailableReason == nil else {
            continuation.yield(unavailableReason ?? String(localized: "Dil modeli kullanılamıyor."))
            return
        }
        // "Bilge, dikteyi bitir" (end dictation) said with the wake phrase still controls dictation.
        if dictation.isActive, DictationCommand.parse(command, language: language) != nil {
            let reply = await dictation.handle(command)
            if !reply.isEmpty { continuation.yield(reply) }
            return
        }
        // "Bunu Ahmet'e gönder" (send this to Ahmet): what was on screen when the command was heard, read only when it points.
        context.screen = ContextIntent.points(command, language: language) ? await ScreenContextReader.snapshot() : nil
        // "Her gün 8'de haberleri oku ve hava durumunu söyle" is one routine; its parts are split when it runs.
        if RoutineRequest.parse(command, language: language) == nil, let parts = CompoundCommand.split(command, language: language) {
            try await handleCompound(command, parts: parts, router: router, unattended: unattended, continuation: continuation)
            return
        }
        try await handleSingle(command, router: router, unattended: unattended, continuation: continuation)
    }

    /// Parts that refer to an earlier result ("…bul ve ona mesaj at") are planned by the large model when
    /// one is selected. Independent parts, or all parts without that model, run one after another as
    /// separate commands, which is also several times faster.
    private func handleCompound(
        _ command: String,
        parts: [String],
        router: CommandRouter,
        unattended: Bool,
        continuation: AsyncThrowingStream<String, any Error>.Continuation
    ) async throws {
        if !unattended, localModel.isEnabled, CompoundCommand.hasDependentParts(parts, language: language) {
            continuation.yield(String(localized: "Tamam, sırayla yapıyorum. "))
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
            try await handleSingle(part, router: router, unattended: unattended, continuation: continuation)
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
            language: language,
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
        unattended: Bool,
        continuation: AsyncThrowingStream<String, any Error>.Continuation
    ) async throws {
        if let reading = context.reading, reading.isCurrent(at: .now), ReadingRequest.isContinuation(command, language: language) {
            try await continueReading(command, into: continuation)
            return
        }
        // "İngilizce maili Türkçe oku": what a tool reads goes through the model, to be read in that language.
        let translation = TranslationRequest.target(in: command)
        switch try await router.route(command, previous: previousTurn) {
        case let .tool(call):
            let viaModel = call.answersWithLanguageModel || translation != nil
            if !viaModel { localModel.turnNeededNoModel() }
            let output = try await run(call, for: command, unattended: unattended, continuation: continuation)
            let result = keepReading(output, of: call, viaModel: viaModel, translation: translation)
            if viaModel, !ToolReply.isFailure(result) {
                let answer = try await answer(command, from: result, translation: translation, into: continuation)
                previousTurn = .init(command: command, action: call.toolName, result: answer)
            } else {
                previousTurn = .init(command: command, action: call.toolName, result: result)
                continuation.yield(ToolReply.spoken(result))
            }
            if context.reading?.hasMore == true { continuation.yield(Self.moreToRead) }
        case .conversation:
            // "İkinci maddeyi açıkla" after a reading: the conversation never saw what the tool read.
            if let reading = context.reading, reading.isCurrent(at: .now), ReadingRequest.refersToReading(command, language: language) {
                let material = String(reading.lastPart.prefix(Self.followUpMaterialLimit))
                let reply = try await answer(command, from: material, translation: translation ?? reading.translation,
                                             into: continuation)
                previousTurn = .init(command: command, action: CommandRouter.conversationAction, result: reply)
                return
            }
            let request = translation.map { command + BrainInstructions.replyLanguage($0, language: language) } ?? command
            let reply = try await streamConversation(request, into: continuation)
            previousTurn = .init(command: command, action: CommandRouter.conversationAction, result: reply)
        }
    }

    /// Keeps what a tool read for "devamını oku" and questions about it, and gives the part to read now:
    /// the first part of a long text, the whole of a short one.
    private func keepReading(_ result: String, of call: PreparedToolCall, viaModel: Bool, translation: SpeechLanguage?) -> String {
        context.reading = nil
        guard !ToolReply.isFailure(result), call.readingLayout != nil || viaModel,
              let reading = ContinuedReading(result, layout: call.readingLayout, answersWithLanguageModel: viaModel,
                                             translation: translation, at: .now)
        else { return result }
        context.reading = reading
        return reading.firstPart
    }

    private func continueReading(_ command: String, into continuation: AsyncThrowingStream<String, any Error>.Continuation) async throws {
        guard var reading = context.reading, let part = reading.next(at: .now) else {
            localModel.turnNeededNoModel()
            let reply = String(localized: "Okuyacak başka bir şey kalmadı, hepsini okudum.")
            previousTurn = .init(command: command, action: Self.continueReadingAction, result: reply)
            continuation.yield(reply)
            return
        }
        context.reading = reading
        let reply: String
        if reading.answersWithLanguageModel {
            reply = try await answer(command, from: part, translation: reading.translation, into: continuation)
        } else {
            localModel.turnNeededNoModel()
            reply = part
            continuation.yield(part)
        }
        previousTurn = .init(command: command, action: Self.continueReadingAction, result: reply)
        if reading.hasMore { continuation.yield(Self.moreToRead) }
    }

    /// Runs a prepared call, asking first when it is risky. Anything but a clear "yes" cancels; with nobody there to
    /// ask (a routine), a risky call is not run at all.
    private func run(
        _ call: PreparedToolCall,
        for command: String,
        unattended: Bool = false,
        continuation: AsyncThrowingStream<String, any Error>.Continuation
    ) async throws -> String {
        if call.risk == .needsConfirmation {
            if unattended {
                Log.tools.info("Routine step \(call.toolName, privacy: .public) needs the user; not run")
                await ActionAuditLog.shared.record(command: command, call: call, decision: .unconfirmed, result: nil)
                return Self.needsUser(command)
            }
            guard let confirmer, let question = call.confirmationQuestion else {
                await ActionAuditLog.shared.record(command: command, call: call, decision: .unconfirmed, result: nil)
                return String(localized: "Bu işlem için onay gerekiyor ama şu an onay alamıyorum, bu yüzden yapmadım.")
            }
            let answer = await confirmer.confirm(question, strict: call.requiresExplicitYes)
            try Task.checkCancellation()
            guard answer == .confirmed else {
                let decision: ActionAuditLog.Decision = answer == .rejected ? .rejected : .unconfirmed
                await ActionAuditLog.shared.record(command: command, call: call, decision: decision, result: nil)
                return answer == .rejected
                    ? String(localized: "Tamam, yapmadım.")
                    : String(localized: "Net bir onay duymadım, bu yüzden yapmadım.")
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
        translation: SpeechLanguage? = nil,
        into continuation: AsyncThrowingStream<String, any Error>.Continuation
    ) async throws -> String {
        let prompt = "Kullanıcının isteği: \(command)\n\nMetin:\n<<<\n\(material)\n>>>"
        let instructions = BrainInstructions.material(language: language)
            + (translation.map { BrainInstructions.translation(to: $0, language: language) } ?? "")
        return try await streamUntrusted(prompt, instructions: instructions, into: continuation)
    }

    /// Streams a reply from a fresh session that has no tools, for prompts carrying untrusted text.
    func streamUntrusted(
        _ prompt: String,
        instructions: String,
        into continuation: AsyncThrowingStream<String, any Error>.Continuation
    ) async throws -> String {
        if localModel.isEnabled {
            do {
                return try await localModel.answer(prompt, instructions: instructions, into: continuation)
            } catch {
                try Self.rethrowIfCancelled(error)
            }
        }
        let session = LanguageModelSession(model: model, instructions: instructions)
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

    /// A whole reply that is not spoken as it forms (a meeting summary), from a session with no tools.
    func generate(
        _ prompt: String,
        instructions: String,
        maxTokens: Int,
        announcingWaitTo continuation: AsyncThrowingStream<String, any Error>.Continuation
    ) async throws -> String {
        if localModel.isEnabled {
            do {
                let reply = try await localModel.complete([.system(instructions), .user(prompt)], maxTokens: maxTokens,
                                                          announcingWaitTo: continuation)
                if !reply.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty { return reply }
            } catch {
                try Self.rethrowIfCancelled(error)
            }
        }
        let session = LanguageModelSession(model: model, instructions: instructions)
        let options = GenerationOptions(temperature: 0.2, maximumResponseTokens: maxTokens)
        return try await session.respond(to: prompt, options: options).content
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
        BrainInstructions.make(memory: memory.promptLines, language: language)
    }

    /// A local-model failure falls back to Apple's model for this turn; cancellation must not.
    private static func rethrowIfCancelled(_ error: any Error) throws {
        if error is CancellationError || Task.isCancelled { throw CancellationError() }
        Log.brain.error("Local model unavailable, using Apple's: \(String(describing: error), privacy: .public)")
    }

    static func needsUser(_ command: String) -> String {
        String(localized: "Bu rutindeki “\(command)” adımı senin onayını gerektiriyor; sen yokken yapmadım. Buradayken söylemen yeterli.")
    }

    static func spokenMessage(for error: any Error) -> String {
        guard let error = error as? LanguageModelError else {
            return String(localized: "Üzgünüm, bir sorun oluştu. Tekrar dener misin?")
        }
        return switch error {
        case .guardrailViolation, .refusal: String(localized: "Bu isteğe yardımcı olamıyorum.")
        case .unsupportedLanguageOrLocale:
            String(localized: "Dil modeli Türkçeyi şu an desteklemiyor. Apple Intelligence dilinin Türkçe olduğunu kontrol et.")
        case .timeout: String(localized: "Yanıt çok uzun sürdü. Tekrar dener misin?")
        default: String(localized: "Üzgünüm, bunu yapamadım. Tekrar dener misin?")
        }
    }
}
