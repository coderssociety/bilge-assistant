import AsistanCore
import Foundation
import FoundationModels

/// Turns a spoken command into either a fully prepared tool call or a conversational turn.
/// The on-device model is unreliable at free-form tool calling (30% correct on our Turkish benchmark),
/// so routing is two constrained generations instead: pick an action from a fixed list, then fill
/// that tool's argument schema. Executing the call stays a separate step.
@MainActor
final class CommandRouter {
    enum Route {
        case tool(PreparedToolCall)
        case conversation
    }

    struct PreviousTurn: Sendable {
        let command: String
        let action: String
        let result: String?
    }

    nonisolated static let conversationAction = "conversation"
    /// Chosen by `MemoryIntent` only. Offering them to the model risked "…hatırlat" reminders being
    /// stored as memories, since "hatırla" and "hatırlat" differ by one letter.
    private static let ruleRoutedActions: [MemoryIntent: String] = [.remember: "remember", .forget: "forget", .list: "listMemories"]
    private static let actionProperty = "action"

    private let model: SystemLanguageModel
    private let language: AssistantLanguage
    private let tools: [String: any AssistantTool]
    private let decisionSchema: GenerationSchema
    private let routerInstructions: String
    private let options = GenerationOptions(samplingMode: .greedy, maximumResponseTokens: 200)
    private var readySession: LanguageModelSession?
    private let fastPath: FastPath
    /// Asked in this order; the first that claims a command takes it.
    private let ruleRouted: [any RuleRoutedTool]

    init(tools: [any AssistantTool], language: AssistantLanguage = .turkish, model: SystemLanguageModel = .default) throws {
        self.model = model
        self.language = language
        self.tools = Dictionary(tools.map { ($0.name, $0) }, uniquingKeysWith: { first, _ in first })
        fastPath = FastPath(tools: self.tools)
        ruleRouted = tools.compactMap { $0 as? any RuleRoutedTool }
        let memoryActions = Set(Self.ruleRoutedActions.values)
        let modelRouted = tools.filter { !memoryActions.contains($0.name) && !($0 is any RuleRoutedTool) }
        let actions = modelRouted.map(\.name) + [Self.conversationAction]
        let actionSchema = DynamicGenerationSchema(name: "Action", anyOf: actions)
        let decision = DynamicGenerationSchema(name: "Decision", properties: [
            .init(name: Self.actionProperty, schema: actionSchema),
        ])
        decisionSchema = try GenerationSchema(root: decision, dependencies: [])
        routerInstructions = RouterInstructions.router(tools: modelRouted, language: language)
    }

    /// Loads the model and processes the routing instructions ahead of time, so the next
    /// command skips that work. Each command gets a fresh session; this one is used once.
    func prewarm() {
        guard readySession == nil else { return }
        let session = LanguageModelSession(model: model, instructions: routerInstructions)
        session.prewarm()
        readySession = session
    }

    func route(_ command: String, previous: PreviousTurn?) async throws -> Route {
        if let tool = ruleRouted.first(where: { $0.claims(command) }) {
            Log.brain.info("Rule-routed: \(tool.name, privacy: .public)")
            return try await prepare(tool, prompt: prompt(command, previous: previous), resolvedCommand: command)
        }
        if let intent = MemoryIntent.parse(command, language: language), let tool = Self.ruleRoutedActions[intent].flatMap({ tools[$0] }) {
            Log.brain.info("Memory request: \(tool.name, privacy: .public)")
            // The spoken words are kept as said: digitizing would turn "sabah yedide" into "07:00".
            return try await prepare(tool, prompt: prompt(command, previous: previous), resolvedCommand: command)
        }
        let resolved = resolve(command)
        if RouteGuard.preRoute(resolved, language: language) != nil { return .conversation }
        if language == .turkish, let intent = QuickIntentParser.parse(resolved), let call = await fastPath.call(for: intent) {
            Log.brain.info("Fast path: \(call.toolName, privacy: .public)")
            return .tool(call)
        }
        let prompt = prompt(resolved, previous: previous)
        let session = readySession ?? LanguageModelSession(model: model, instructions: routerInstructions)
        readySession = nil
        defer { prewarm() }
        let response = try await session.respond(to: prompt, schema: decisionSchema, options: options)
        let modelAction = try response.content.value(String.self, forProperty: Self.actionProperty)
        let action = language == .turkish
            ? RouteGuard.review(action: modelAction, command: resolved)
            : EnglishRouteGuard.review(action: modelAction, command: resolved)
        Log.brain.info("Routed to \(action, privacy: .public) (model: \(modelAction, privacy: .public))")
        guard let tool = tools[action] else { return .conversation }
        return try await prepare(tool, prompt: prompt, resolvedCommand: resolved)
    }

    private func prepare<T: AssistantTool>(_ tool: T, prompt: String, resolvedCommand: String) async throws -> Route {
        let arguments: T.Arguments
        if let empty = tool.emptyArguments() {
            arguments = empty
        } else if let direct = tool.arguments(fromCommand: resolvedCommand) {
            arguments = direct
        } else {
            let session = LanguageModelSession(model: model, instructions: RouterInstructions.extraction(for: tool, language: language))
            let extracted = try await session.respond(to: prompt, generating: T.Arguments.self, options: options).content
            arguments = tool.refine(extracted, command: resolvedCommand)
        }
        if tool.prefersConversation(for: arguments) {
            Log.brain.info("\(tool.name, privacy: .public) handed to conversation")
            return .conversation
        }
        return .tool(await tool.makeCall(arguments))
    }

    /// Turkish number words and times of day become digits for the parsers. English is left as said:
    /// the Turkish rules would turn "on" and "one" into 10 and "bin" into 1000.
    private func resolve(_ command: String) -> String {
        language == .turkish ? TurkishTimeOfDay.resolve(TurkishNumberParser.digitize(command)) : command
    }

    private func prompt(_ command: String, previous: PreviousTurn?) -> String {
        let labels = language == .english
            ? (request: "Request", previous: "Previous request", action: "action", result: "Previous result", current: "Current request")
            : (request: "İstek", previous: "Önceki istek", action: "eylem", result: "Önceki sonuç", current: "Şimdiki istek")
        guard let previous else { return "\(labels.request): \(command)" }
        var context = "\(labels.previous): \(previous.command) (\(labels.action): \(previous.action))"
        if let result = previous.result { context += "\n\(labels.result): \(result.prefix(300))" }
        return context + "\n\(labels.current): \(command)"
    }
}
