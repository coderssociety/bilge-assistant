import AsistanCore
import Foundation

/// Lists, starts and loads models in LM Studio through its loopback API and `lms` tool.
struct LMStudioClient: Sendable {
    struct Model: Decodable, Sendable, Identifiable, Hashable {
        let id: String
        let type: String
        let arch: String?
        let quantization: String?
        let state: String

        var isLoaded: Bool { state == "loaded" }
        /// LM Studio lists formats it cannot load (e.g. JANG quantizations) without an architecture.
        var isChatModel: Bool { (type == "llm" || type == "vlm") && arch != nil }
    }

    private struct ModelList: Decodable { let data: [Model] }

    private static let baseURL = URL(string: "http://127.0.0.1:1234")!
    /// Room for the multi-step planner: tool catalog, steps and their results.
    private static let contextLength = 16384
    private static let loadTimeout: Duration = .seconds(240)
    private static let startupPolls = 10

    static var commandLineTool: URL {
        FileManager.default.homeDirectoryForCurrentUser.appending(path: ".lmstudio/bin/lms")
    }

    static var isInstalled: Bool {
        FileManager.default.isExecutableFile(atPath: commandLineTool.path(percentEncoded: false))
    }

    func chatModels() async throws -> [Model] {
        let (data, response) = try await URLSession.shared.data(from: Self.baseURL.appending(path: "api/v0/models"))
        try LocalModelEndpoint.check(response)
        return try JSONDecoder().decode(ModelList.self, from: data).data.filter(\.isChatModel)
    }

    func startServerIfNeeded() async throws {
        guard Self.isInstalled else { throw LocalModelServerError.notInstalled("LM Studio") }
        if (try? await chatModels()) != nil { return }
        try Task.checkCancellation()
        try await runTool(["server", "start"], timeout: .seconds(30))
        for _ in 0..<Self.startupPolls {
            if (try? await chatModels()) != nil { return }
            try await Task.sleep(for: .milliseconds(500))
        }
        throw LocalModelServerError.serverUnavailable("LM Studio")
    }

    /// Starts the server and loads the model when needed (15–30 s for a large model).
    /// `loadedByUs` tells the caller whether it should unload the model when switching away.
    func prepare(_ id: String) async throws -> (endpoint: LocalModelEndpoint, loadedByUs: Bool) {
        try await startServerIfNeeded()
        guard let models = try? await chatModels() else { throw LocalModelServerError.serverUnavailable("LM Studio") }
        guard let model = models.first(where: { $0.id == id }) else {
            throw LocalModelServerError.loadFailed(String(localized: "\(id) LM Studio'da yok."))
        }
        let endpoint = Self.endpoint(for: model)
        if model.isLoaded { return (endpoint, false) }
        Log.brain.info("Loading \(id, privacy: .public) in LM Studio")
        do {
            try await runTool(["load", id, "--context-length", String(Self.contextLength), "-y"], timeout: Self.loadTimeout)
            guard try await chatModels().first(where: { $0.id == id })?.isLoaded == true else {
                throw LocalModelServerError.loadFailed(id)
            }
            return (endpoint, true)
        } catch {
            // LM Studio may finish a load even when `lms` was stopped. The caller may be cancelled,
            // so the unload runs in a task of its own and is awaited so it can't race a later load.
            await Task { await unload(id) }.value
            throw error
        }
    }

    /// Starts `lms unload` without waiting, for when the app is quitting or the caller is cancelled.
    static func unloadInBackground(_ id: String) {
        let process = Process()
        process.executableURL = commandLineTool
        process.arguments = ["unload", id]
        process.standardOutput = FileHandle.nullDevice
        process.standardError = FileHandle.nullDevice
        do {
            try process.run()
        } catch {
            Log.brain.error("Could not start lms unload: \(error.localizedDescription, privacy: .public)")
        }
    }

    func unload(_ id: String) async {
        do {
            try await runTool(["unload", id], timeout: .seconds(30))
        } catch {
            Log.brain.error("Could not unload \(id, privacy: .public): \(error.localizedDescription, privacy: .public)")
        }
    }

    private static func endpoint(for model: Model) -> LocalModelEndpoint {
        let usesChatML = model.arch?.hasPrefix("qwen") ?? false
        return LocalModelEndpoint(baseURL: baseURL, modelID: model.id,
                                  promptStyle: usesChatML ? .chatML : .chat(disablesThinking: false))
    }

    private func runTool(_ arguments: [String], timeout: Duration) async throws {
        let output = try await ProcessRunner.run(Self.commandLineTool.path(percentEncoded: false), arguments, timeout: timeout)
        guard output.status == 0 else {
            Log.brain.error("lms \(arguments.first ?? "", privacy: .public) failed: \(output.standardError, privacy: .public)")
            throw LocalModelServerError.loadFailed(output.standardError.isEmpty ? "lms \(output.status)" : output.standardError)
        }
    }
}
