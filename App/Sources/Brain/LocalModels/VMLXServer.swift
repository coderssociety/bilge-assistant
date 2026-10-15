import Foundation

/// Serves models LM Studio cannot load (JANG quantizations such as Gemma 4 31B) with the `vmlx` tool.
/// Between conversations the model is put into vMLX's deep sleep: weights leave memory (22 GB → under 1 GB)
/// but the process stays, so waking takes ~5 s instead of a ~6.5 s restart. Other clients wake it on demand.
/// The process itself is only stopped if Bilge started it, when the app quits or the choice changes.
@MainActor
final class VMLXServer {
    static let shared = VMLXServer()

    private static let baseURL = URL(string: "http://127.0.0.1:8000")!
    private static let startupTimeout: Duration = .seconds(180)
    private static let pollInterval: Duration = .milliseconds(250)
    private static let shutdownTimeout: Duration = .seconds(5)
    /// vMLX's default cap is 10% of the volume (~83 GB here), far more than a few warm prompt prefixes need.
    private static let blockDiskCacheMaxGB = 4
    private var ownedProcess: Process?

    nonisolated static var executable: URL {
        FileManager.default.homeDirectoryForCurrentUser.appending(path: ".local/bin/vmlx")
    }

    nonisolated static var isInstalled: Bool {
        FileManager.default.isExecutableFile(atPath: executable.path(percentEncoded: false))
    }

    private nonisolated static var modelsDirectory: URL {
        FileManager.default.homeDirectoryForCurrentUser.appending(path: ".lmstudio/models")
    }

    /// "publisher/name" ids of downloaded models that need vMLX (they carry a `jang_config.json`).
    nonisolated static func installedModels() -> [String] {
        let files = FileManager.default
        let publishers = (try? files.contentsOfDirectory(atPath: modelsDirectory.path(percentEncoded: false))) ?? []
        return publishers.flatMap { publisher -> [String] in
            let folder = modelsDirectory.appending(path: publisher)
            let names = (try? files.contentsOfDirectory(atPath: folder.path(percentEncoded: false))) ?? []
            return names
                .filter { files.fileExists(atPath: folder.appending(path: "\($0)/jang_config.json").path(percentEncoded: false)) }
                .map { "\(publisher)/\($0)" }
        }
        .sorted()
    }

    nonisolated static func runningModels() async throws -> [String] {
        struct ModelList: Decodable {
            struct Entry: Decodable { let id: String }
            let data: [Entry]
        }
        let (data, response) = try await URLSession.shared.data(from: baseURL.appending(path: "v1/models"))
        try LocalModelEndpoint.check(response)
        return try JSONDecoder().decode(ModelList.self, from: data).data.map(\.id)
    }

    /// Models served with weights in memory; empty while the server is down or in deep sleep.
    nonisolated static func awakeModels() async -> [String] {
        struct Health: Decodable { let status: String }
        guard let (data, _) = try? await URLSession.shared.data(from: baseURL.appending(path: "health")),
              (try? JSONDecoder().decode(Health.self, from: data))?.status == "healthy"
        else { return [] }
        return (try? await runningModels()) ?? []
    }

    /// Reuses a running server or starts one (about 6 s once the weights are in the file cache).
    func prepare(_ id: String) async throws -> LocalModelEndpoint {
        let running = try? await Self.runningModels()
        try Task.checkCancellation()
        if let running {
            guard running.contains(id) else {
                let served = running.joined(separator: ", ")
                throw LocalModelServerError.loadFailed(String(localized: "vMLX şu an başka bir model sunuyor (\(served))."))
            }
            do {
                try await admin("wake")
            } catch {
                // An abandoned wake still completes on the server; put the weights back to sleep.
                // The caller may be cancelled, so this runs in a task of its own.
                await Task { await sleep() }.value
                throw error
            }
            return endpoint(for: id)
        }
        // A process Bilge started that is not answering yet is waited for, never started twice.
        if ownedProcess?.isRunning != true { try start(id) }
        do {
            try await waitUntilServing(id)
            return endpoint(for: id)
        } catch {
            stopImmediately()
            throw error
        }
    }

    private func waitUntilServing(_ id: String) async throws {
        let deadline = ContinuousClock.now + Self.startupTimeout
        while ContinuousClock.now < deadline {
            try await Task.sleep(for: Self.pollInterval)
            guard ownedProcess?.isRunning == true else { throw LocalModelServerError.serverUnavailable("vMLX") }
            if let running = try? await Self.runningModels(), running.contains(id) { return }
        }
        throw LocalModelServerError.serverUnavailable("vMLX")
    }

    /// When switching models: ends the process Bilge started, or puts the user's server to sleep.
    func stopOrSleep() async {
        if ownedProcess != nil { await stop() } else { await sleep() }
    }

    /// Called when the app quits. `sleepingServer` puts a server Bilge used but did not start to sleep;
    /// that request is waited for briefly, since nothing runs after the app exits.
    func shutDown(sleepingServer: Bool) {
        if ownedProcess != nil {
            stopImmediately()
            return
        }
        guard sleepingServer else { return }
        var request = URLRequest(url: Self.baseURL.appending(path: "admin/deep-sleep"), timeoutInterval: 2)
        request.httpMethod = "POST"
        let done = DispatchSemaphore(value: 0)
        URLSession.shared.dataTask(with: request) { _, _, _ in done.signal() }.resume()
        _ = done.wait(timeout: .now() + 2)
    }

    /// Unloads the weights but keeps the server; a wake or any inference request loads them again.
    func sleep() async {
        do {
            try await admin("deep-sleep")
            Log.brain.info("vMLX model asleep")
        } catch LocalModelServerError.badResponse(409) {
            return
        } catch {
            Log.brain.error("vMLX deep sleep failed: \(error.localizedDescription, privacy: .public)")
        }
    }

    /// Wake blocks until the model is loaded again, so it gets a long timeout.
    private func admin(_ action: String) async throws {
        var request = URLRequest(url: Self.baseURL.appending(path: "admin/\(action)"), timeoutInterval: Self.startupTimeout / .seconds(1))
        request.httpMethod = "POST"
        let (_, response) = try await URLSession.shared.data(for: request)
        try LocalModelEndpoint.check(response)
    }

    /// Stops the server only if Bilge started it, and waits until it has exited and freed the port.
    func stop() async {
        guard let process = ownedProcess else { return }
        ownedProcess = nil
        process.terminate()
        let deadline = ContinuousClock.now + Self.shutdownTimeout
        while process.isRunning, ContinuousClock.now < deadline {
            try? await Task.sleep(for: .milliseconds(100))
        }
        if process.isRunning { kill(process.processIdentifier, SIGKILL) }
        Log.brain.info("Stopped vMLX")
    }

    func stopImmediately() {
        guard let process = ownedProcess else { return }
        ownedProcess = nil
        if process.isRunning { process.terminate() }
    }

    private func start(_ id: String) throws {
        guard Self.isInstalled else { throw LocalModelServerError.notInstalled("vMLX") }
        let folder = try modelFolder(for: id)
        let process = Process()
        process.executableURL = Self.executable
        process.arguments = ["serve", folder.path(percentEncoded: false), "--host", "127.0.0.1",
                             "--port", String(Self.baseURL.port ?? 8000), "--served-model-name", id,
                             "--block-disk-cache-max-gb", String(Self.blockDiskCacheMaxGB)]
        var environment = ProcessInfo.processInfo.environment
        environment["PATH"] = "/opt/homebrew/bin:/usr/local/bin:/usr/bin:/bin"
        process.environment = environment
        let log = try Self.logFile()
        process.standardOutput = log
        process.standardError = log
        try process.run()
        ownedProcess = process
        Log.brain.info("Started vMLX for \(id, privacy: .public)")
    }

    /// The id comes from settings, so it must name a folder inside the models directory.
    private func modelFolder(for id: String) throws -> URL {
        let parts = id.split(separator: "/").map(String.init)
        guard parts.count == 2, parts.allSatisfy({ !$0.hasPrefix(".") }) else {
            throw LocalModelServerError.loadFailed(id)
        }
        let folder = Self.modelsDirectory.appending(path: id)
        guard FileManager.default.fileExists(atPath: folder.path(percentEncoded: false)) else {
            throw LocalModelServerError.loadFailed(String(localized: "\(id) bulunamadı."))
        }
        return folder
    }

    private static func logFile() throws -> FileHandle {
        let directory = FileManager.default.homeDirectoryForCurrentUser.appending(path: "Library/Logs/Bilge")
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let file = directory.appending(path: "vmlx.log")
        FileManager.default.createFile(atPath: file.path(percentEncoded: false), contents: nil)
        return try FileHandle(forWritingTo: file)
    }

    private func endpoint(for id: String) -> LocalModelEndpoint {
        LocalModelEndpoint(baseURL: Self.baseURL, modelID: id, promptStyle: .chat(disablesThinking: true))
    }
}
