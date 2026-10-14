import AsistanCore
import CryptoKit
import Foundation

enum ModelDownloadError: LocalizedError {
    case invalidModel
    case listingFailed(Int)
    case nothingToDownload
    case notEnoughSpace(needed: Int64)
    case transferFailed(String)
    case corrupted(String)

    var errorDescription: String? {
        switch self {
        case .invalidModel: "Model adı geçersiz."
        case let .listingFailed(status): "Model dosyaları listelenemedi (\(status))."
        case .nothingToDownload: "Modelde indirilecek dosya bulunamadı."
        case let .notEnoughSpace(needed):
            "Diskte yer yok; \(needed.formatted(.byteCount(style: .file))) boş alan gerekiyor."
        case let .transferFailed(file): "\(file) indirilemedi."
        case let .corrupted(file): "\(file) bozuk indi; tekrar dene."
        }
    }
}

/// Downloads a model repository from Hugging Face at a pinned commit. Large files are checked against the
/// SHA-256 that Hugging Face publishes, and the model only becomes visible once every file is in place.
struct HuggingFaceDownloader: Sendable {
    private static let host = URL(string: "https://huggingface.co")!
    private static let progressInterval: Duration = .milliseconds(250)
    /// Kept free beyond the download itself, so the Mac does not run out of space.
    private static let spareSpace: Int64 = 2_000_000_000
    private static let hashChunkSize = 8 << 20

    struct Progress: Sendable {
        let received: Int64
        let total: Int64
        var fraction: Double { total > 0 ? min(1, Double(received) / Double(total)) : 0 }
    }

    private let session: URLSession = {
        let configuration = URLSessionConfiguration.ephemeral
        configuration.timeoutIntervalForRequest = 60
        configuration.waitsForConnectivity = false
        return URLSession(configuration: configuration)
    }()

    func download(
        _ model: DownloadableModel, into destination: URL, progress: @escaping @Sendable (Progress) -> Void
    ) async throws {
        guard ModelRepository.isValidID(model.id), ModelRepository.isPinnedRevision(model.revision) else {
            throw ModelDownloadError.invalidModel
        }
        let files = ModelRepository.neededFiles(try await listFiles(of: model))
        guard files.contains(where: { $0.path.hasSuffix(".safetensors") }) else { throw ModelDownloadError.nothingToDownload }
        guard let total = ModelRepository.totalSize(files) else { throw ModelDownloadError.invalidModel }
        let partial = Self.partialFolder(for: destination)
        try FileManager.default.createDirectory(at: partial, withIntermediateDirectories: true)
        try checkSpace(for: total - Self.alreadyPresent(files, in: partial), at: partial)

        var done: Int64 = 0
        for file in files {
            try Task.checkCancellation()
            let target = partial.appending(path: file.path)
            if try Self.isComplete(file, at: target) {
                done += file.size
                continue
            }
            let base = done
            try await fetch(file, of: model, to: target) { progress(Progress(received: base + $0, total: total)) }
            done += file.size
            progress(Progress(received: done, total: total))
        }
        try? FileManager.default.removeItem(at: destination)
        try FileManager.default.moveItem(at: partial, to: destination)
    }

    /// Where files gather until the download is complete, beside the final folder.
    static func partialFolder(for destination: URL) -> URL {
        destination.deletingLastPathComponent().appending(path: ".\(destination.lastPathComponent).partial")
    }

    private func listFiles(of model: DownloadableModel) async throws -> [RepositoryFile] {
        let url = Self.host.appending(path: "api/models/\(model.id)/tree/\(model.revision)")
            .appending(queryItems: [URLQueryItem(name: "recursive", value: "true")])
        let (data, response) = try await session.data(from: url)
        let status = (response as? HTTPURLResponse)?.statusCode ?? 0
        guard status == 200 else { throw ModelDownloadError.listingFailed(status) }
        return try JSONDecoder().decode([RepositoryFile].self, from: data)
    }

    private func fetch(
        _ file: RepositoryFile, of model: DownloadableModel, to target: URL, received: @escaping @Sendable (Int64) -> Void
    ) async throws {
        let url = Self.host.appending(path: "\(model.id)/resolve/\(model.revision)/\(file.path)")
        try FileManager.default.createDirectory(at: target.deletingLastPathComponent(), withIntermediateDirectories: true)
        try? FileManager.default.removeItem(at: target)
        try await transfer(url, to: target, name: file.path, received: received)
        guard Self.size(of: target) == file.size else {
            try? FileManager.default.removeItem(at: target)
            throw ModelDownloadError.corrupted(file.path)
        }
        if let expected = file.expectedSHA256, try Self.sha256(of: target) != expected {
            try? FileManager.default.removeItem(at: target)
            throw ModelDownloadError.corrupted(file.path)
        }
    }

    /// One file, reporting received bytes while it arrives; cancelling the caller cancels the transfer.
    private func transfer(_ url: URL, to target: URL, name: String, received: @escaping @Sendable (Int64) -> Void) async throws {
        let box = TaskBox()
        let reporter = Task {
            while !Task.isCancelled {
                try? await Task.sleep(for: Self.progressInterval)
                if !Task.isCancelled, let task = box.task { received(task.countOfBytesReceived) }
            }
        }
        defer { reporter.cancel() }
        try await withTaskCancellationHandler {
            try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, any Error>) in
                let task = session.downloadTask(with: url) { location, response, error in
                    let status = (response as? HTTPURLResponse)?.statusCode ?? 0
                    guard let location, error == nil, status == 200 else {
                        let cancelled = (error as? URLError)?.code == .cancelled
                        continuation.resume(throwing: cancelled ? CancellationError() : ModelDownloadError.transferFailed(name))
                        return
                    }
                    // The temporary file is removed when this handler returns.
                    do {
                        try FileManager.default.moveItem(at: location, to: target)
                        continuation.resume()
                    } catch {
                        continuation.resume(throwing: error)
                    }
                }
                box.task = task
                task.resume()
                // Cancelled before the task existed: the handler above had nothing to cancel.
                if Task.isCancelled { task.cancel() }
            }
        } onCancel: {
            box.task?.cancel()
        }
    }

    /// Whether an interrupted download left files behind.
    static func hasLeftovers(for destination: URL) -> Bool {
        FileManager.default.fileExists(atPath: partialFolder(for: destination).path(percentEncoded: false))
    }

    private func checkSpace(for bytes: Int64, at folder: URL) throws {
        let values = try folder.resourceValues(forKeys: [.volumeAvailableCapacityForImportantUsageKey])
        guard let available = values.volumeAvailableCapacityForImportantUsage else { return }
        let needed = bytes + Self.spareSpace
        if available < needed { throw ModelDownloadError.notEnoughSpace(needed: needed) }
    }

    private static func alreadyPresent(_ files: [RepositoryFile], in folder: URL) -> Int64 {
        files.filter { size(of: folder.appending(path: $0.path)) == $0.size }.reduce(0) { $0 + $1.size }
    }

    /// A file left by an interrupted download counts only if its size matches; large files are hashed again.
    private static func isComplete(_ file: RepositoryFile, at url: URL) throws -> Bool {
        guard size(of: url) == file.size else { return false }
        guard let expected = file.expectedSHA256 else { return true }
        do {
            return try sha256(of: url) == expected
        } catch is CancellationError {
            throw CancellationError()
        } catch {
            return false
        }
    }

    private static func size(of url: URL) -> Int64? {
        (try? FileManager.default.attributesOfItem(atPath: url.path(percentEncoded: false))[.size] as? NSNumber)?.int64Value
    }

    private static func sha256(of url: URL) throws -> String {
        let handle = try FileHandle(forReadingFrom: url)
        defer { try? handle.close() }
        var hasher = SHA256()
        while let chunk = try handle.read(upToCount: hashChunkSize), !chunk.isEmpty {
            try Task.checkCancellation()
            hasher.update(data: chunk)
        }
        return hasher.finalize().map { String(format: "%02x", $0) }.joined()
    }
}

/// Hands the transfer to the cancellation handler and the progress reporter, which run elsewhere.
private final class TaskBox: @unchecked Sendable {
    private let lock = NSLock()
    private var stored: URLSessionDownloadTask?

    var task: URLSessionDownloadTask? {
        get { lock.withLock { stored } }
        set { lock.withLock { stored = newValue } }
    }
}
