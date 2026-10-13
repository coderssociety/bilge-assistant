import Foundation

/// Serves models LM Studio cannot load (JANG quantizations such as Gemma 4 31B) with the `vmlx` tool.
/// A server the user started is reused; one Bilge started is stopped again when no longer needed.
@MainActor
final class VMLXServer {
    static let shared = VMLXServer()

    private static let baseURL = URL(string: "http://127.0.0.1:8000")!
    private static let startupTimeout: Duration = .seconds(180)
    private static let pollInterval: Duration = .seconds(1)
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

    /// Reuses a running server or starts one; loading a 30B model takes about 10–20 s.
    func prepare(_ id: String) async throws -> LocalModelEndpoint {
        if let running = try? await Self.runningModels() {
            guard running.contains(id) else {
                throw LocalModelServerError.loadFailed("vMLX şu an başka bir model sunuyor (\(running.joined(separator: ", "))).")
            }
            return endpoint(for: id)
        }
        try start(id)
        do {
            try await waitUntilServing(id)
            return endpoint(for: id)
        } catch {
            stop()
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

    /// Stops the server only if Bilge started it.
    func stop() {
        guard let process = ownedProcess else { return }
        ownedProcess = nil
        if process.isRunning { process.terminate() }
        Log.brain.info("Stopped vMLX")
    }

    private func start(_ id: String) throws {
        guard Self.isInstalled else { throw LocalModelServerError.notInstalled("vMLX") }
        let folder = try modelFolder(for: id)
        let process = Process()
        process.executableURL = Self.executable
        process.arguments = ["serve", folder.path(percentEncoded: false), "--host", "127.0.0.1",
                             "--port", String(Self.baseURL.port ?? 8000), "--served-model-name", id]
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
            throw LocalModelServerError.loadFailed("\(id) bulunamadı.")
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
