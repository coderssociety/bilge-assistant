import AsistanCore
import MLX
import MLXLMCommon

/// Keeps the model's state after reading a long system prompt (instructions, the multi-step tool list), so
/// later replies only read what follows it. Without this every planner step re-read about four thousand
/// tokens: 11–16 s per step on a 27B model, against under 2 s with a server's prompt cache.
///
/// Only used inside a model turn (`BuiltInChatModel.turns`), which is why plain mutable state is safe here.
final class PromptPrefixCache: @unchecked Sendable {
    private struct Entry {
        let tokens: [Int]
        let cache: [KVCache]
    }

    /// Shorter prefixes are read quickly enough that keeping their state is not worth the memory.
    private static let minimumPrefix = 256
    /// Conversation, screen answers and the planner each have their own system prompt.
    private static let capacity = 3

    private var entries: [Entry] = []

    /// The part of `input` still to be read and the cache to read it into; nil cache means start afresh.
    func start(
        for input: LMInput, systemPrompt: String?, options: [String: any Sendable],
        context: ModelContext, parameters: GenerateParameters
    ) async throws -> (input: LMInput, cache: [KVCache]?) {
        let tokens = Self.tokens(of: input)
        if let index = entries.firstIndex(where: { $0.tokens.count < tokens.count && tokens.starts(with: $0.tokens) }) {
            let entry = entries.remove(at: index)
            entries.insert(entry, at: 0)
            return (Self.input(Array(tokens[entry.tokens.count...])), entry.cache.map { $0.copy() })
        }
        guard let systemPrompt else { return (input, nil) }
        // The system prompt rendered alone shares its tokens with the full prompt up to the first message after it.
        let probe = try await context.processor.prepare(
            input: UserInput(chat: [.system(systemPrompt), .user("")], additionalContext: options))
        let prefixLength = zip(tokens, Self.tokens(of: probe)).prefix { $0 == $1 }.count
        guard prefixLength >= Self.minimumPrefix, prefixLength < tokens.count else { return (input, nil) }

        let cache = try context.model.newCache(parameters: parameters)
        // Creating the iterator reads the whole given prompt into the cache.
        _ = try TokenIterator(input: Self.input(Array(tokens[..<prefixLength])), model: context.model,
                              cache: cache, parameters: parameters)
        entries.insert(Entry(tokens: Array(tokens[..<prefixLength]), cache: cache.map { $0.copy() }), at: 0)
        entries = Array(entries.prefix(Self.capacity))
        return (Self.input(Array(tokens[prefixLength...])), cache)
    }

    private static func tokens(of input: LMInput) -> [Int] {
        input.text.tokens.reshaped(-1).asArray(Int32.self).map(Int.init)
    }

    private static func input(_ tokens: [Int]) -> LMInput {
        LMInput(tokens: MLXArray(tokens.map(Int32.init)))
    }
}
