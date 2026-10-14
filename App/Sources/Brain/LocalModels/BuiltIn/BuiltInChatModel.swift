import AsistanCore
import Foundation
import MLX
import MLXLLM
import MLXLMCommon
import Synchronization
import Tokenizers

/// A catalog model Bilge downloaded, or an MLX model the user put in its models folder, running inside
/// Bilge on the GPU; no other program is needed.
/// Its memory goes back once the lifecycle drops it and `releaseMemory` empties MLX's buffer cache.
struct BuiltInChatModel: LoadedChatModel {
    /// Buffers MLX keeps for reuse between replies; the rest goes back to the system.
    private static let bufferCacheLimit = 20 << 20
    private static let loadedID = Mutex<String?>(nil)
    private static let turns = TurnLock()
    /// Nucleus sampling as the model publishers recommend. A repetition penalty is deliberately not used:
    /// it pushed Gemma 4 into its special audio tokens.
    private static let topP: Float = 0.95
    private static let topK = 64

    /// Qwen 3.x thinks for seconds before answering unless the chat template is told not to;
    /// templates without the switch ignore it.
    private static let templateOptions: [String: any Sendable] = ["enable_thinking": false]

    private let container: ModelContainer
    private let prefixCache = PromptPrefixCache()

    static func isAvailable(_ choice: LocalModelChoice) -> Bool {
        (try? folder(for: choice)) != nil
    }

    static func isLoaded(_ choice: LocalModelChoice) -> Bool {
        loadedID.withLock { $0 == choice.storageKey }
    }

    /// Reads the weights from disk (a few seconds once they are in the file cache). Never touches the network.
    static func load(_ choice: LocalModelChoice) async throws -> BuiltInChatModel {
        let folder = try folder(for: choice)
        Memory.cacheLimit = bufferCacheLimit
        let container = try await LLMModelFactory.shared.loadContainer(from: folder, using: TransformersTokenizerLoader())
        loadedID.withLock { $0 = choice.storageKey }
        return BuiltInChatModel(container: container)
    }

    private static func folder(for choice: LocalModelChoice) throws -> URL {
        switch choice.server {
        case .builtIn:
            guard let model = ModelCatalog.model(id: choice.modelID) else {
                throw LocalModelServerError.loadFailed("\(choice.modelID) tanınmıyor.")
            }
            guard ModelDownloads.isDownloaded(model) else { throw LocalModelServerError.notInstalled(model.name) }
            return try ModelDownloads.folder(for: model)
        case .custom:
            return try CustomModels.folder(named: choice.modelID)
        case .lmStudio, .vmlx:
            throw LocalModelServerError.loadFailed(choice.modelID)
        }
    }

    static func releaseMemory() {
        loadedID.withLock { $0 = nil }
        Memory.clearCache()
    }

    func streamReply(messages: [ChatMessage], temperature: Double, maxTokens: Int) -> AsyncThrowingStream<String, any Error> {
        let templateOptions = Self.templateOptions
        let parameters = GenerateParameters(maxTokens: maxTokens, temperature: Float(temperature), topP: Self.topP, topK: Self.topK)
        let container = container
        let prefixCache = prefixCache
        let systemPrompt = messages.first { $0.role == .system }?.content
        return AsyncThrowingStream { continuation in
            let task = Task {
                // The decoding loop outlives `perform`, so replies take turns: a cancelled reply's last
                // step must not run on the weights while the next reply is reading the prompt.
                await Self.turns.acquire()
                var decoding: Task<Void, Never>?
                do {
                    try Task.checkCancellation()
                    let (generations, loop) = try await container.perform { context in
                        let input = try await context.processor.prepare(
                            input: UserInput(chat: messages.map(Self.message), additionalContext: templateOptions))
                        let start = try await prefixCache.start(for: input, systemPrompt: systemPrompt, options: templateOptions,
                                                                context: context, parameters: parameters)
                        let iterator = try TokenIterator(input: start.input, model: context.model, cache: start.cache,
                                                         parameters: parameters)
                        return MLXLMCommon.generateTask(promptTokenCount: start.input.text.tokens.size,
                                                        modelConfiguration: context.configuration,
                                                        tokenizer: context.tokenizer, iterator: iterator)
                    }
                    decoding = loop
                    // Cancelling this task ends the iteration, which stops decoding after the current token.
                    for await generation in generations {
                        if case let .chunk(text) = generation {
                            let spoken = Self.withoutControlTokens(text)
                            if !spoken.isEmpty { continuation.yield(spoken) }
                        }
                    }
                    try Task.checkCancellation()
                    continuation.finish()
                } catch {
                    continuation.finish(throwing: error)
                }
                await decoding?.value
                await Self.turns.release()
            }
            continuation.onTermination = { _ in task.cancel() }
        }
    }

    func warmUp(instructions: String) async throws {
        for try await _ in streamReply(messages: [.system(instructions), .user("Merhaba")], temperature: 0, maxTokens: 1) {}
    }

    /// Control tokens such as Gemma 4's "<audio|>" can slip into the text and would be read aloud.
    private static func withoutControlTokens(_ text: String) -> String {
        text.replacing(/<\|?[a-z_]+\|>|<\|[a-z_]+\|?>/, with: "")
    }

    private static func message(_ message: ChatMessage) -> Chat.Message {
        switch message.role {
        case .system: .system(message.content)
        case .user: .user(message.content)
        case .assistant: .assistant(message.content)
        }
    }
}

/// Reads the tokenizer and chat template from the model folder with swift-transformers.
private struct TransformersTokenizerLoader: TokenizerLoader {
    func load(from directory: URL) async throws -> any MLXLMCommon.Tokenizer {
        TokenizerBridge(upstream: try await AutoTokenizer.from(modelFolder: directory))
    }
}

private struct TokenizerBridge: MLXLMCommon.Tokenizer {
    let upstream: any Tokenizers.Tokenizer

    func encode(text: String, addSpecialTokens: Bool) -> [Int] {
        upstream.encode(text: text, addSpecialTokens: addSpecialTokens)
    }

    func decode(tokenIds: [Int], skipSpecialTokens: Bool) -> String {
        upstream.decode(tokens: tokenIds, skipSpecialTokens: skipSpecialTokens)
    }

    func convertTokenToId(_ token: String) -> Int? { upstream.convertTokenToId(token) }
    func convertIdToToken(_ id: Int) -> String? { upstream.convertIdToToken(id) }

    var bosToken: String? { upstream.bosToken }
    var eosToken: String? { upstream.eosToken }
    var unknownToken: String? { upstream.unknownToken }

    func applyChatTemplate(
        messages: [[String: any Sendable]], tools: [[String: any Sendable]]?, additionalContext: [String: any Sendable]?
    ) throws -> [Int] {
        do {
            return try upstream.applyChatTemplate(messages: messages, tools: tools, additionalContext: additionalContext)
        } catch Tokenizers.TokenizerError.missingChatTemplate {
            throw MLXLMCommon.TokenizerError.missingChatTemplate
        }
    }
}

/// Lets one generation at a time use the model.
private actor TurnLock {
    private var isBusy = false
    private var waiting: [CheckedContinuation<Void, Never>] = []

    func acquire() async {
        guard isBusy else {
            isBusy = true
            return
        }
        await withCheckedContinuation { waiting.append($0) }
    }

    func release() {
        if waiting.isEmpty {
            isBusy = false
        } else {
            waiting.removeFirst().resume()
        }
    }
}
