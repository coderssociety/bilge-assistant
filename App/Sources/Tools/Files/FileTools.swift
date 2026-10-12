import AppKit
import FoundationModels

/// File lookup is limited to the user's home folder; nothing here modifies files.
struct FileTool: AssistantTool {
    let name = "files"
    let description = "Dosya bulur (Spotlight), bulunan dosyayı açar, son indirilen dosyayı açar ya da Masaüstü/İndirilenler/Belgeler klasörünü açar."
    private static let maxResults = 5

    @Generable
    enum Action {
        case find, openFound, openLatestDownload, openFolder
    }

    @Generable
    enum Folder {
        case desktop, downloads, documents, home
    }

    @Generable
    struct Arguments {
        var action: Action
        @Guide(description: "'find' ve 'openFound' için dosya adında geçen kelimeler")
        var query: String?
        @Guide(description: "'openFolder' için klasör")
        var folder: Folder?
    }

    func call(arguments: Arguments) async throws -> String {
        do {
            switch arguments.action {
            case .find:
                guard let query = arguments.query else { return ToolReply.failure("Aranacak dosya adı belirtilmedi.") }
                let results = try await search(query)
                guard !results.isEmpty else { return "'\(query)' ile eşleşen dosya bulunamadı." }
                let list = results.map { "\($0.lastPathComponent) (\(Self.describeLocation($0)))" }
                return "Bulunan dosyalar: " + list.joined(separator: "; ")
            case .openFound:
                guard let query = arguments.query else { return ToolReply.failure("Açılacak dosya adı belirtilmedi.") }
                guard let file = try await search(query).first else { return "'\(query)' ile eşleşen dosya bulunamadı." }
                return await open(file)
            case .openLatestDownload:
                guard let latest = try Self.latestFile(in: Self.url(for: .downloads)) else {
                    return "İndirilenler klasörü boş."
                }
                return await open(latest)
            case .openFolder:
                return await open(Self.url(for: arguments.folder ?? .home))
            }
        } catch {
            return ToolReply.failure(error)
        }
    }

    private func search(_ query: String) async throws -> [URL] {
        let home = FileManager.default.homeDirectoryForCurrentUser.path
        let output = try await ProcessRunner.run("/usr/bin/mdfind", ["-onlyin", home, "-name", query])
        let urls = output.standardOutput.split(separator: "\n").map { URL(filePath: String($0)) }
            .filter { !$0.path.contains("/Library/") && !$0.lastPathComponent.hasPrefix(".") }
        return Self.sortedByRecency(urls).prefix(Self.maxResults).map { $0 }
    }

    /// Opening an app, script or installer would run code the user never explicitly approved,
    /// so those are only revealed in Finder.
    @MainActor
    private func open(_ url: URL) -> String {
        if Self.isExecutable(url) {
            NSWorkspace.shared.activateFileViewerSelecting([url])
            return "\(url.lastPathComponent) çalıştırılabilir bir dosya; güvenlik için açmadım, Finder'da gösterdim."
        }
        return NSWorkspace.shared.open(url)
            ? "\(url.lastPathComponent) açıldı."
            : ToolReply.failure("\(url.lastPathComponent) açılamadı.")
    }

    private static let executableExtensions: Set<String> = [
        "app", "command", "sh", "zsh", "bash", "tool", "pkg", "mpkg", "terminal", "workflow", "scpt",
        "applescript", "jar", "py", "rb", "pl", "dmg", "action", "prefpane", "kext",
    ]

    private static func isExecutable(_ url: URL) -> Bool {
        if executableExtensions.contains(url.pathExtension.lowercased()) { return true }
        var isDirectory: ObjCBool = false
        guard FileManager.default.fileExists(atPath: url.path, isDirectory: &isDirectory) else { return false }
        return !isDirectory.boolValue && FileManager.default.isExecutableFile(atPath: url.path)
    }

    private static func url(for folder: Folder) -> URL {
        let fileManager = FileManager.default
        return switch folder {
        case .desktop: fileManager.urls(for: .desktopDirectory, in: .userDomainMask)[0]
        case .downloads: fileManager.urls(for: .downloadsDirectory, in: .userDomainMask)[0]
        case .documents: fileManager.urls(for: .documentDirectory, in: .userDomainMask)[0]
        case .home: fileManager.homeDirectoryForCurrentUser
        }
    }

    private static func latestFile(in directory: URL) throws -> URL? {
        let items = try FileManager.default.contentsOfDirectory(
            at: directory, includingPropertiesForKeys: [.contentModificationDateKey], options: .skipsHiddenFiles)
        return sortedByRecency(items).first
    }

    private static func sortedByRecency(_ urls: [URL]) -> [URL] {
        urls.map { ($0, (try? $0.resourceValues(forKeys: [.contentModificationDateKey]))?.contentModificationDate ?? .distantPast) }
            .sorted { $0.1 > $1.1 }
            .map(\.0)
    }

    private static func describeLocation(_ url: URL) -> String {
        url.deletingLastPathComponent().path.replacingOccurrences(of: NSHomeDirectory(), with: "~")
    }
}
