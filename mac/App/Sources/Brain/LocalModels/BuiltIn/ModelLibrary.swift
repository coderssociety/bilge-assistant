import AppKit
import AsistanCore
import Foundation

/// MLX models already on the Mac outside Bilge's own folder: LM Studio's downloads, the Hugging Face cache
/// and folders the user added. They run in place, so nothing takes the disk twice. GGUF models are left
/// out: only LM Studio itself can run them.
enum ModelLibrary {
    enum Source: Hashable {
        case lmStudio
        case huggingFace
        case folder(URL)

        var label: String {
            switch self {
            case .lmStudio: "LM Studio"
            case .huggingFace: String(localized: "Hugging Face önbelleği")
            case let .folder(url): url.lastPathComponent
            }
        }
    }

    private static let userFoldersKey = "modelSearchFolders"
    /// Deep enough for "<folder>/<publisher>/<model>"; a model folder itself is not searched further.
    private static let maxDepth = 3
    /// Keeps a folder like the home folder from turning a scan into a crawl.
    private static let maxFoldersVisited = 2_000

    static var userFolders: [URL] {
        (UserDefaults.standard.stringArray(forKey: userFoldersKey) ?? [])
            .filter { $0.hasPrefix("/") }
            .map { URL(filePath: $0, directoryHint: .isDirectory) }
    }

    /// Asks for a folder to search; true when one was added.
    @MainActor
    static func addFolder() -> Bool {
        let panel = NSOpenPanel()
        panel.canChooseDirectories = true
        panel.canChooseFiles = false
        panel.prompt = String(localized: "Ekle")
        panel.message = String(localized: "MLX modellerinin bulunduğu klasörü seç.")
        guard panel.runModal() == .OK, let url = panel.url else { return false }
        let paths = userFolders.map { $0.path(percentEncoded: false) }
        let path = url.path(percentEncoded: false)
        guard !paths.contains(path) else { return false }
        UserDefaults.standard.set(paths + [path], forKey: userFoldersKey)
        return true
    }

    static func removeFolder(_ folder: URL) {
        let remaining = userFolders.filter { $0 != folder }.map { $0.path(percentEncoded: false) }
        UserDefaults.standard.set(remaining, forKey: userFoldersKey)
    }

    static func scan() -> [CustomModels.Model] {
        var seen = Set<String>()
        return roots().flatMap { source, root in
            modelFolders(in: source, root: root).compactMap { folder, name -> CustomModels.Model? in
                guard seen.insert(path(of: folder.resolvingSymlinksInPath())).inserted else { return nil }
                return CustomModels.Model(name: name, bytes: CustomModels.size(of: folder),
                                          status: CustomModels.inspect(folder), source: source.label, folder: folder)
            }
        }
    }

    /// The path comes from settings, so it must lie inside one of the searched folders.
    static func folder(path: String) throws -> URL {
        let roots = roots().map { Self.path(of: $0.root) }
        guard ModelSearchRoots.contains(path, roots: roots) else { throw LocalModelServerError.loadFailed(path) }
        let folder = URL(filePath: path, directoryHint: .isDirectory)
        guard case .ready = CustomModels.inspect(folder) else { throw LocalModelServerError.notInstalled(folder.lastPathComponent) }
        return folder
    }

    private static func roots() -> [(source: Source, root: URL)] {
        let environment = ProcessInfo.processInfo.environment
        let userHome = FileManager.default.homeDirectoryForCurrentUser
        return [(.lmStudio, lmStudioModels(userHome: userHome)),
                (.huggingFace, HuggingFaceCacheFolder.hubRoot(environment: environment, userHome: userHome))]
            + userFolders.map { (.folder($0), $0) }
    }

    private static func lmStudioModels(userHome: URL) -> URL {
        let pointer = try? String(contentsOf: userHome.appending(path: LMStudioModelsFolder.homePointerFile), encoding: .utf8)
        let home = LMStudioModelsFolder.home(userHome: userHome, pointer: pointer)
        let settings = try? Data(contentsOf: home.appending(path: LMStudioModelsFolder.settingsFile))
        return LMStudioModelsFolder.modelsRoot(home: home, settings: settings)
    }

    /// Model folders with the name to show for each.
    private static func modelFolders(in source: Source, root: URL) -> [(URL, String)] {
        switch source {
        case .huggingFace:
            subfolders(of: root).compactMap { repo in
                guard let id = HuggingFaceCacheFolder.repoID(cacheFolderName: repo.lastPathComponent),
                      let snapshot = currentSnapshot(of: repo), hasWeights(snapshot) else { return nil }
                return (snapshot, id)
            }
        case .lmStudio, .folder:
            search(root, depth: maxDepth).map { folder in
                (folder, String(path(of: folder).dropFirst(path(of: root).count + 1)))
            }
        }
    }

    /// The revision refs/main points at, or the newest snapshot when there is no ref.
    private static func currentSnapshot(of repo: URL) -> URL? {
        let snapshots = repo.appending(path: "snapshots", directoryHint: .isDirectory)
        if let revision = try? String(contentsOf: repo.appending(path: "refs/main"), encoding: .utf8)
            .trimmingCharacters(in: .whitespacesAndNewlines),
           MLXModelFolder.isValidName(revision) {
            let folder = snapshots.appending(path: revision, directoryHint: .isDirectory)
            if FileManager.default.fileExists(atPath: folder.path(percentEncoded: false)) { return folder }
        }
        return subfolders(of: snapshots).max { modified($0) < modified($1) }
    }

    private static func search(_ root: URL, depth: Int) -> [URL] {
        var found: [URL] = []
        var queue = [(root, 0)]
        var visited = 0
        while !queue.isEmpty, visited < maxFoldersVisited {
            let (folder, level) = queue.removeFirst()
            visited += 1
            if level > 0, hasWeights(folder) {
                found.append(folder)
            } else if level < depth {
                queue += subfolders(of: folder).map { ($0, level + 1) }
            }
        }
        return found.sorted { $0.path.localizedStandardCompare($1.path) == .orderedAscending }
    }

    private static func subfolders(of folder: URL) -> [URL] {
        let entries = (try? FileManager.default.contentsOfDirectory(
            at: folder, includingPropertiesForKeys: [.isDirectoryKey], options: .skipsHiddenFiles)) ?? []
        return entries.filter {
            MLXModelFolder.isValidName($0.lastPathComponent)
                && (try? $0.resolvingSymlinksInPath().resourceValues(forKeys: [.isDirectoryKey]).isDirectory) == true
        }
    }

    /// A config.json next to .safetensors files: an MLX language model or something close enough to report on.
    private static func hasWeights(_ folder: URL) -> Bool {
        let names = (try? FileManager.default.contentsOfDirectory(atPath: folder.path(percentEncoded: false))) ?? []
        return names.contains("config.json") && names.contains { $0.hasSuffix(".safetensors") }
    }

    /// Without the trailing slash, so the same folder always gives the same stored path.
    static func path(of folder: URL) -> String {
        let path = folder.path(percentEncoded: false)
        return path.count > 1 && path.hasSuffix("/") ? String(path.dropLast()) : path
    }

    private static func modified(_ url: URL) -> Date {
        (try? url.resourceValues(forKeys: [.contentModificationDateKey]).contentModificationDate) ?? .distantPast
    }
}
