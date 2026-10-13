import AsistanCore
import Foundation

enum LocalModelError: Error {
    /// Still starting or loading; this turn uses Apple's model while it finishes in the background.
    case notReady
    case emptyReply
}

/// Answers conversation and screen questions with a larger model served on this Mac (LM Studio or vMLX).
/// Routing and Mac actions stay on Apple's model; this only ever produces text and has no tools.
/// A turn never waits for a server to start or load: until the model is ready, Apple's model answers.
@MainActor
final class LocalModelResponder {
    private let lmStudio = LMStudioClient()
    private(set) var choice: LocalModelChoice?
    private var ready: LocalModelEndpoint?
    private var preparation: Task<Void, Never>?
    /// Frees what Bilge itself loaded or started for the current choice, when switching away.
    private var release: (@MainActor () -> Void)?
    private var history = ChatHistory()
    /// After a failed start, the server is not retried for a while so each turn isn't slowed by it.
    private var unavailableUntil: ContinuousClock.Instant?
    private static let retryDelay: Duration = .seconds(60)

    var isEnabled: Bool { choice != nil }

    func select(_ newChoice: LocalModelChoice?) {
        guard newChoice != choice else { return }
        preparation?.cancel()
        preparation = nil
        ready = nil
        release?()
        release = nil
        unavailableUntil = nil
        choice = newChoice
        history = ChatHistory()
        prewarm()
    }

    /// Stops a server Bilge started; called when the app quits.
    func shutDown() {
        release?()
        release = nil
    }

    func prewarm() {
        guard let choice, ready == nil, preparation == nil else { return }
        if let unavailableUntil, ContinuousClock.now < unavailableUntil { return }
        preparation = Task {
            do {
                finishPreparation(of: choice, with: .success(try await prepare(choice)))
            } catch {
                finishPreparation(of: choice, with: .failure(error))
            }
        }
    }

    private func prepare(_ choice: LocalModelChoice) async throws -> LocalModelEndpoint {
        switch choice.server {
        case .lmStudio:
            let (endpoint, loadedByUs) = try await lmStudio.prepare(choice.modelID)
            if loadedByUs {
                release = { [lmStudio] in Task { await lmStudio.unload(choice.modelID) } }
            }
            return endpoint
        case .vmlx:
            let endpoint = try await VMLXServer.shared.prepare(choice.modelID)
            release = { VMLXServer.shared.stop() }
            return endpoint
        }
    }

    /// For benchmarks: waits until the selected model is loaded. Returns false if it could not be.
    func waitUntilReady() async -> Bool {
        prewarm()
        await preparation?.value
        return ready != nil
    }

    func resetConversation() {
        history = ChatHistory()
    }

    func converse(
        _ command: String,
        instructions: String,
        into continuation: AsyncThrowingStream<String, any Error>.Continuation
    ) async throws -> String {
        let messages = [ChatMessage.system(instructions)] + history.messages + [.user(command)]
        let reply = try await stream(messages, temperature: 0.6, into: continuation)
        history = history.appending(user: command, assistant: reply)
        return reply
    }

    func answer(
        _ prompt: String,
        instructions: String,
        into continuation: AsyncThrowingStream<String, any Error>.Continuation
    ) async throws -> String {
        try await stream([.system(instructions), .user(prompt)], temperature: 0.3, into: continuation)
    }

    /// Throws only when nothing was said yet, so the caller can fall back to Apple's model;
    /// a failure mid-reply keeps what was already spoken.
    private func stream(
        _ messages: [ChatMessage],
        temperature: Double,
        into continuation: AsyncThrowingStream<String, any Error>.Continuation
    ) async throws -> String {
        guard let endpoint = ready else {
            prewarm()
            throw LocalModelError.notReady
        }
        var emitted = ""
        do {
            let chunks = endpoint.streamReply(messages: messages, temperature: temperature,
                                              maxTokens: AssistantBrain.maximumResponseTokens)
            for try await chunk in chunks {
                let text = emitted.isEmpty ? String(chunk.drop(while: \.isWhitespace)) : chunk
                guard !text.isEmpty else { continue }
                continuation.yield(text)
                emitted += text
            }
            try Task.checkCancellation()
        } catch {
            if Task.isCancelled || error is CancellationError { throw CancellationError() }
            // The model may have been unloaded or the server stopped; check again before the next turn.
            ready = nil
            guard !emitted.isEmpty else { throw error }
            Log.brain.error("Local model stopped mid-reply: \(String(describing: error), privacy: .public)")
        }
        guard !emitted.isEmpty else { throw LocalModelError.emptyReply }
        return emitted
    }

    private func finishPreparation(of prepared: LocalModelChoice, with result: Result<LocalModelEndpoint, any Error>) {
        guard prepared == choice else { return }
        preparation = nil
        switch result {
        case let .success(endpoint):
            ready = endpoint
            Log.brain.info("Local model ready: \(prepared.storageKey, privacy: .public)")
        case let .failure(error):
            guard !(error is CancellationError) else { return }
            unavailableUntil = .now + Self.retryDelay
            Log.brain.error("Local model unavailable: \(String(describing: error), privacy: .public)")
        }
    }
}

