import AsistanCore
import Foundation

enum LocalModelError: Error {
    /// Could not be started or loaded in time; this turn uses Apple's model.
    case notReady
    case emptyReply
}

/// Answers conversation and screen questions with a larger model served on this Mac (LM Studio or vMLX).
/// Routing and Mac actions stay on Apple's model; this only ever produces text and has no tools.
/// Loading starts when the wake phrase is heard, so it mostly overlaps with the user speaking;
/// the model is freed again according to `keepAlive`.
@MainActor
final class LocalModelResponder {
    /// A turn waits this long in silence for a model that is still loading, then says so.
    private static let silentWait: Duration = .milliseconds(1500)
    /// Covers a cold load after a restart (15–30 s); past this the turn falls back to Apple's model.
    private static let maximumWait: Duration = .seconds(30)
    private static let pollInterval: Duration = .milliseconds(100)
    static let waitingNotice = "Bir saniye. "

    private let lifecycle = LocalModelLifecycle()
    private var history = ChatHistory()

    var isEnabled: Bool { lifecycle.choice != nil }

    var keepAlive: LocalModelKeepAlive {
        get { lifecycle.keepAlive }
        set { lifecycle.keepAlive = newValue }
    }

    func select(_ choice: LocalModelChoice?) {
        history = ChatHistory()
        lifecycle.select(choice)
    }

    func launched() {
        if keepAlive == .always { lifecycle.load() }
    }

    /// The wake phrase was heard: start loading while the user is still speaking.
    func conversationWillStart() {
        lifecycle.cancelIdleUnload()
        lifecycle.load()
    }

    func conversationEnded() {
        history = ChatHistory()
        lifecycle.conversationEnded()
    }

    /// The turn went to a Mac action; a model still loading for it is likely not needed (most such
    /// conversations are commands only), so it is freed once loaded unless a question asks for it.
    func turnNeededNoModel() {
        lifecycle.abandonLoadIfNotReady()
    }

    func shutDown() {
        lifecycle.shutDown()
    }

    /// For benchmarks: waits until the selected model is loaded. Returns false if it could not be.
    func waitUntilReady() async -> Bool {
        lifecycle.load()
        await lifecycle.waitForLoad()
        return lifecycle.ready != nil
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

    /// A whole reply at once, for the multi-step planner, whose JSON is parsed rather than spoken.
    func complete(
        _ messages: [ChatMessage],
        maxTokens: Int,
        announcingWaitTo continuation: AsyncThrowingStream<String, any Error>.Continuation
    ) async throws -> String {
        let endpoint = try await readyEndpoint(announcingWaitTo: continuation)
        var reply = ""
        do {
            for try await chunk in endpoint.streamReply(messages: messages, temperature: 0, maxTokens: maxTokens) {
                reply += chunk
            }
            try Task.checkCancellation()
        } catch {
            if Task.isCancelled || error is CancellationError { throw CancellationError() }
            lifecycle.endpointFailed()
            throw error
        }
        return reply
    }

    /// Throws only when nothing was said yet, so the caller can fall back to Apple's model;
    /// a failure mid-reply keeps what was already spoken.
    private func stream(
        _ messages: [ChatMessage],
        temperature: Double,
        into continuation: AsyncThrowingStream<String, any Error>.Continuation
    ) async throws -> String {
        let endpoint = try await readyEndpoint(announcingWaitTo: continuation)
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
            // The model may have been unloaded or the server stopped; load afresh next time.
            lifecycle.endpointFailed()
            guard !emitted.isEmpty else { throw error }
            Log.brain.error("Local model stopped mid-reply: \(String(describing: error), privacy: .public)")
        }
        guard !emitted.isEmpty else { throw LocalModelError.emptyReply }
        return emitted
    }

    /// Waits for a model that is still loading, saying "Bir saniye." if it takes noticeably long.
    private func readyEndpoint(
        announcingWaitTo continuation: AsyncThrowingStream<String, any Error>.Continuation
    ) async throws -> LocalModelEndpoint {
        lifecycle.cancelIdleUnload()
        lifecycle.load()
        let started = ContinuousClock.now
        var announced = false
        while true {
            if let ready = lifecycle.ready { return ready }
            guard lifecycle.isLoading, ContinuousClock.now - started < Self.maximumWait else {
                throw LocalModelError.notReady
            }
            if !announced, ContinuousClock.now - started >= Self.silentWait {
                announced = true
                continuation.yield(Self.waitingNotice)
            }
            try await Task.sleep(for: Self.pollInterval)
        }
    }
}
