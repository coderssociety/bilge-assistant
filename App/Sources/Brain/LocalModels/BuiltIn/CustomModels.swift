import AppKit
import AsistanCore
import Foundation

/// MLX models the user downloaded themselves and put in ~/Library/Application Support/Asistan/Models/Kendi Modellerim,
/// one folder per model. A symbolic link to a model kept elsewhere (for example in LM Studio) works too.
enum CustomModels {
    struct Model: Identifiable, Hashable {
        let name: String
        let bytes: Int64
        let status: MLXModelFolder.Status
        var id: String { name }
    }

    private static let folderName = "Kendi Modellerim"

    static func directory() throws -> URL {
        try ModelStorage.directory(for: folderName)
    }

    static func scan() -> [Model] {
        guard let directory = try? directory(),
              let entries = try? FileManager.default.contentsOfDirectory(
                  at: directory, includingPropertiesForKeys: [.isDirectoryKey], options: .skipsHiddenFiles)
        else { return [] }
        return entries
            .filter { (try? $0.resolvingSymlinksInPath().resourceValues(forKeys: [.isDirectoryKey]).isDirectory) == true }
            .filter { MLXModelFolder.isValidName($0.lastPathComponent) }
            .map { Model(name: $0.lastPathComponent, bytes: size(of: $0.resolvingSymlinksInPath()), status: inspect($0)) }
            .sorted { $0.name.localizedStandardCompare($1.name) == .orderedAscending }
    }

    /// The folder of a model chosen by name; the name comes from settings, so it must stay inside the directory.
    static func folder(named name: String) throws -> URL {
        guard MLXModelFolder.isValidName(name) else { throw LocalModelServerError.loadFailed(name) }
        let folder = try directory().appending(path: name, directoryHint: .isDirectory)
        guard case .ready = inspect(folder) else { throw LocalModelServerError.notInstalled(name) }
        return folder
    }

    static func isAvailable(_ name: String) -> Bool {
        (try? folder(named: name)) != nil
    }

    static func revealInFinder() {
        guard let directory = try? directory() else { return }
        NSWorkspace.shared.activateFileViewerSelecting([directory])
    }

    private static func inspect(_ folder: URL) -> MLXModelFolder.Status {
        let names = (try? FileManager.default.contentsOfDirectory(atPath: folder.path(percentEncoded: false))) ?? []
        let config = try? Data(contentsOf: folder.appending(path: "config.json"))
        return MLXModelFolder.inspect(fileNames: names, config: config)
    }

    private static func size(of folder: URL) -> Int64 {
        let files = FileManager.default.enumerator(at: folder, includingPropertiesForKeys: [.fileSizeKey])
        var total: Int64 = 0
        while let file = files?.nextObject() as? URL {
            total += Int64((try? file.resourceValues(forKeys: [.fileSizeKey]).fileSize) ?? 0)
        }
        return total
    }
}
