import AsistanCore
import Foundation
import Observation

/// Which catalog models are on disk and which are downloading. One instance, shared by onboarding and
/// settings, so a download started in one keeps running and shows in the other.
@MainActor
@Observable
final class ModelDownloads {
    enum State: Equatable {
        case notDownloaded
        case downloading(Double)
        case downloaded
        case failed(String)
    }

    private(set) var states: [String: State] = [:]
    /// Called when a model is complete on disk, so a selected model can load right away.
    var onDownloaded: ((DownloadableModel) -> Void)?
    private var tasks: [String: Task<Void, Never>] = [:]
    private let downloader = HuggingFaceDownloader()

    init() {
        for model in ModelCatalog.models {
            states[model.id] = Self.isDownloaded(model) ? .downloaded : .notDownloaded
        }
    }

    func state(of model: DownloadableModel) -> State {
        states[model.id] ?? .notDownloaded
    }

    var downloadedModels: [DownloadableModel] {
        ModelCatalog.models.filter { state(of: $0) == .downloaded }
    }

    func start(_ model: DownloadableModel) {
        guard tasks[model.id] == nil else { return }
        states[model.id] = .downloading(0)
        tasks[model.id] = Task { [downloader] in
            do {
                let folder = try Self.folder(for: model)
                // The download task already holds the manager, which lives as long as the app.
                try await downloader.download(model, into: folder) { progress in
                    Task { @MainActor in
                        guard case .downloading = self.states[model.id] else { return }
                        self.states[model.id] = .downloading(progress.fraction)
                    }
                }
                states[model.id] = .downloaded
                Log.brain.info("Downloaded \(model.id, privacy: .public)")
                onDownloaded?(model)
            } catch where Task.isCancelled || error is CancellationError || (error as? URLError)?.code == .cancelled {
                states[model.id] = .notDownloaded
            } catch {
                Log.brain.error("Download of \(model.id, privacy: .public) failed: \(error.localizedDescription, privacy: .public)")
                states[model.id] = .failed(error.localizedDescription)
            }
            tasks[model.id] = nil
        }
    }

    /// Stops a download; files that arrived completely are kept, so a later start skips them.
    func cancel(_ model: DownloadableModel) {
        tasks[model.id]?.cancel()
    }

    /// Files an interrupted download left behind, which `delete` removes.
    func hasLeftovers(_ model: DownloadableModel) -> Bool {
        guard tasks[model.id] == nil, let folder = try? Self.folder(for: model) else { return false }
        return HuggingFaceDownloader.hasLeftovers(for: folder)
    }

    /// Removes the model and anything an interrupted download left; only when it is not downloading.
    func delete(_ model: DownloadableModel) throws {
        guard tasks[model.id] == nil else { return }
        let folder = try Self.folder(for: model)
        for url in [folder, HuggingFaceDownloader.partialFolder(for: folder)] where FileManager.default.fileExists(atPath: url.path(percentEncoded: false)) {
            try FileManager.default.removeItem(at: url)
        }
        states[model.id] = .notDownloaded
    }

    /// ~/Library/Application Support/Asistan/Models/llm/<owner>/<name>
    nonisolated static func folder(for model: DownloadableModel) throws -> URL {
        guard ModelRepository.isValidID(model.id) else { throw ModelDownloadError.invalidModel }
        return try ModelStorage.directory(for: "llm").appending(path: model.id, directoryHint: .isDirectory)
    }

    nonisolated static func isDownloaded(_ model: DownloadableModel) -> Bool {
        guard let folder = try? folder(for: model) else { return false }
        return FileManager.default.fileExists(atPath: folder.appending(path: "config.json").path(percentEncoded: false))
    }
}
