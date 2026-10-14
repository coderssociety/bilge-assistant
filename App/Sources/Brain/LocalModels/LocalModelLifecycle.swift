import AsistanCore
import Foundation

/// Loads and frees the large conversation model. Every load and release runs as one step of a serial
/// chain, so a release never overlaps a load of the same model. Each load also carries the generation
/// it was started in: once `unload` moves on, a late load frees what it acquired instead of
/// publishing it.
@MainActor
final class LocalModelLifecycle {
    /// What Bilge must free again. A model the user loaded in LM Studio is never listed here.
    enum Owned: Sendable {
        case lmStudioModel(String)
        /// Any vMLX server Bilge used: put to deep sleep after a conversation, it wakes on demand.
        case vmlx
        /// A model running inside Bilge; its memory goes back once nothing holds it.
        case builtIn
    }

    private static let retryDelay: Duration = .seconds(60)

    private let lmStudio = LMStudioClient()
    private(set) var choice: LocalModelChoice?
    private(set) var ready: (any LoadedChatModel)?
    private(set) var isLoading = false
    private var owned: Owned?
    private var generation = 0
    private var chain: Task<Void, Never>?
    private var loadStep: Task<Void, Never>?
    private var idleUnload: Task<Void, Never>?
    /// Set when the turn turned out to be a Mac action: the load runs on (cancelling and reloading
    /// would cost more if a question follows) but the model is freed as soon as it is in.
    private var discardWhenLoaded = false
    /// After a failed start the server is not retried for a while, so turns are not slowed by it.
    private var unavailableUntil: ContinuousClock.Instant?

    var keepAlive: LocalModelKeepAlive = .untilConversationEnds {
        didSet {
            guard keepAlive != oldValue else { return }
            cancelIdleUnload()
            if keepAlive == .always { load() } else { scheduleIdleUnload() }
        }
    }

    func select(_ newChoice: LocalModelChoice?) {
        guard newChoice != choice else { return }
        unload(stoppingServer: true)
        unavailableUntil = nil
        choice = newChoice
        if keepAlive == .always { load() }
    }

    func load() {
        discardWhenLoaded = false
        guard let choice, ready == nil, !isLoading else { return }
        // Still downloading: Apple's model answers meanwhile, and the next turn loads it once it is in.
        if choice.server == .builtIn, !BuiltInChatModel.isDownloaded(choice.modelID) { return }
        if let unavailableUntil, ContinuousClock.now < unavailableUntil { return }
        isLoading = true
        let started = generation
        loadStep = enqueue { [weak self] in await self?.runLoad(choice, generation: started) }
    }

    /// For benchmarks.
    func waitForLoad() async {
        await loadStep?.value
    }

    func cancelIdleUnload() {
        idleUnload?.cancel()
        idleUnload = nil
    }

    func conversationEnded() {
        cancelIdleUnload()
        scheduleIdleUnload()
    }

    /// The turn went to a Mac action: a model still loading is freed once it is in, a ready one stays.
    func abandonLoadIfNotReady() {
        guard keepAlive == .untilConversationEnds, isLoading else { return }
        discardWhenLoaded = true
    }

    /// The server failed mid-use; free what is left and load afresh next time.
    func endpointFailed() {
        unload()
    }

    /// Called when the app quits: nothing can be awaited, so freeing is only started.
    func shutDown() {
        generation += 1
        loadStep?.cancel()
        if case let .lmStudioModel(id) = owned { LMStudioClient.unloadInBackground(id) }
        VMLXServer.shared.shutDown(sleepingServer: owned.map { if case .vmlx = $0 { true } else { false } } ?? false)
        owned = nil
    }

    // MARK: - Steps

    private func scheduleIdleUnload() {
        guard let limit = keepAlive.idleLimit, ready != nil || isLoading || owned != nil else { return }
        guard limit > .zero else {
            unload()
            return
        }
        idleUnload = Task {
            try? await Task.sleep(for: limit)
            guard !Task.isCancelled else { return }
            unload()
        }
    }

    /// `stoppingServer` also ends a vMLX process Bilge started, instead of only putting it to sleep.
    private func unload(stoppingServer: Bool = false) {
        cancelIdleUnload()
        discardWhenLoaded = false
        generation += 1
        loadStep?.cancel()
        loadStep = nil
        isLoading = false
        ready = nil
        let released = owned
        owned = nil
        guard released != nil || stoppingServer else { return }
        enqueue { [weak self] in await self?.release(released, stoppingServer: stoppingServer) }
        Log.brain.info("Freeing local model \(self.choice?.storageKey ?? "", privacy: .public)")
    }

    private func runLoad(_ choice: LocalModelChoice, generation started: Int) async {
        defer {
            if started == generation {
                isLoading = false
                loadStep = nil
            }
        }
        guard started == generation, !Task.isCancelled else { return }
        var acquired: Owned?
        do {
            let (endpoint, owner) = try await prepare(choice)
            acquired = owner
            try Task.checkCancellation()
            try await endpoint.warmUp(instructions: BrainInstructions.make())
            guard started == generation, !Task.isCancelled else { throw CancellationError() }
            owned = acquired
            ready = endpoint
            Log.brain.info("Local model ready: \(choice.storageKey, privacy: .public)")
            if discardWhenLoaded { unload() }
        } catch {
            // This step may itself be cancelled, so freeing runs in a task of its own.
            if let acquired {
                await Task { await self.release(acquired, stoppingServer: false) }.value
            }
            guard started == generation, !(error is CancellationError), !Task.isCancelled else { return }
            unavailableUntil = .now + Self.retryDelay
            Log.brain.error("Local model unavailable: \(String(describing: error), privacy: .public)")
        }
    }

    private func prepare(_ choice: LocalModelChoice) async throws -> (any LoadedChatModel, Owned?) {
        switch choice.server {
        case .lmStudio:
            let (endpoint, loadedByUs) = try await lmStudio.prepare(choice.modelID)
            return (endpoint, loadedByUs ? .lmStudioModel(choice.modelID) : nil)
        case .vmlx:
            return (try await VMLXServer.shared.prepare(choice.modelID), .vmlx)
        case .builtIn:
            return (try await BuiltInChatModel.load(choice.modelID), .builtIn)
        }
    }

    private func release(_ released: Owned?, stoppingServer: Bool) async {
        switch released {
        case let .lmStudioModel(id):
            await lmStudio.unload(id)
        case .vmlx:
            if stoppingServer { await VMLXServer.shared.stopOrSleep() } else { await VMLXServer.shared.sleep() }
        case .builtIn:
            BuiltInChatModel.releaseMemory()
        case nil:
            // A server Bilge started and already put to sleep is still running.
            if stoppingServer { await VMLXServer.shared.stop() }
        }
    }

    @discardableResult
    private func enqueue(_ step: @escaping @MainActor () async -> Void) -> Task<Void, Never> {
        let previous = chain
        let task = Task {
            await previous?.value
            await step()
        }
        chain = task
        return task
    }
}
