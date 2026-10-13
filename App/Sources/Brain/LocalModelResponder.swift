import AsistanCore
import Foundation

enum LocalModelError: Error {
    /// Still starting or loading; this turn uses Apple's model while it finishes in the background.
    case notReady
    case emptyReply
}

/// Answers conversation and screen questions with a larger model served by LM Studio on this Mac.
/// Routing and Mac actions stay on Apple's model; this only ever produces text and has no tools.
/// A turn never waits for LM Studio to start or load: until the model is ready, Apple's model answers.
@MainActor
final class LocalModelResponder {
    private let client = LMStudioClient()
    private(set) var modelID: String?
    private var ready: LMStudioClient.Model?
    private var preparation: Task<Void, Never>?
    private var history = ChatHistory()
    /// After a failed start, LM Studio is not retried for a while so each turn isn't slowed by it.
    private var unavailableUntil: ContinuousClock.Instant?
    private static let retryDelay: Duration = .seconds(60)

    var isEnabled: Bool { modelID != nil }

    func select(_ id: String?) {
        guard id != modelID else { return }
        preparation?.cancel()
        preparation = nil
        ready = nil
        unavailableUntil = nil
        modelID = id
        history = ChatHistory()
        prewarm()
    }

    func prewarm() {
        guard let modelID, ready == nil, preparation == nil else { return }
        if let unavailableUntil, ContinuousClock.now < unavailableUntil { return }
        preparation = Task { [client] in
            do {
                finishPreparation(of: modelID, with: .success(try await client.prepare(modelID)))
            } catch {
                finishPreparation(of: modelID, with: .failure(error))
            }
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
        guard let model = ready else {
            prewarm()
            throw LocalModelError.notReady
        }
        var emitted = ""
        do {
            let chunks = client.streamReply(model: model, messages: messages, temperature: temperature,
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
            // The model may have been unloaded in LM Studio; check it again before the next turn.
            ready = nil
            guard !emitted.isEmpty else { throw error }
            Log.brain.error("Local model stopped mid-reply: \(String(describing: error), privacy: .public)")
        }
        guard !emitted.isEmpty else { throw LocalModelError.emptyReply }
        return emitted
    }

    private func finishPreparation(of id: String, with result: Result<LMStudioClient.Model, any Error>) {
        guard id == modelID else { return }
        preparation = nil
        switch result {
        case let .success(model):
            ready = model
            Log.brain.info("LM Studio model ready: \(id, privacy: .public)")
        case let .failure(error):
            guard !(error is CancellationError) else { return }
            unavailableUntil = .now + Self.retryDelay
            Log.brain.error("LM Studio model unavailable: \(String(describing: error), privacy: .public)")
        }
    }
}

