import AppKit
import AsistanCore
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
        @Guide(description: "'find' ve 'openFound' için dosya adında geçen kelimeler; söylendiyse türü ('pdf', 'excel', 'resim', 'sunum') ve zamanı ('dün', 'geçen hafta') da yaz")
        var query: String?
        @Guide(description: "'openFolder' için klasör")
        var folder: Folder?
    }

    /// The kind and time said in the command are kept even when the extracted query left them out
    /// ("son indirdiğim PDF'i aç" must not open the newest .stl).
    func refine(_ arguments: Arguments, command: String) -> Arguments {
        guard arguments.action != .openFolder else { return arguments }
        var refined = arguments
        let query = FileQuery.parse(arguments.query ?? "").addingFilters(of: FileQuery.parse(command))
        refined.query = query.isEmpty ? nil : query.text
        return refined
    }

    func call(arguments: Arguments) async throws -> String {
        do {
            switch arguments.action {
            case .find:
                guard let query = arguments.query else { return ToolReply.failure(String(localized: "Aranacak dosya adı belirtilmedi.")) }
                let results = try await FileSearch.find(query, limit: Self.maxResults)
                guard !results.isEmpty else { return String(localized: "'\(query)' ile eşleşen dosya bulunamadı.") }
                let list = results.map { "\($0.lastPathComponent) (\(FileSearch.describeLocation($0)))" }
                return String(localized: "Bulunan dosyalar: \(list.joined(separator: "; "))")
            case .openFound:
                guard let query = arguments.query else { return ToolReply.failure(String(localized: "Açılacak dosya adı belirtilmedi.")) }
                guard let file = try await FileSearch.find(query, limit: Self.maxResults).first else {
                    return String(localized: "'\(query)' ile eşleşen dosya bulunamadı.")
                }
                return await open(file)
            case .openLatestDownload:
                let extensions = FileQuery.parse(arguments.query ?? "").extensions
                guard let latest = try Self.latestFile(in: Self.url(for: .downloads), extensions: extensions) else {
                    return extensions.isEmpty
                        ? String(localized: "İndirilenler klasörü boş.")
                        : String(localized: "İndirilenler'de bu türde bir dosya yok.")
                }
                return await open(latest)
            case .openFolder:
                return await open(Self.url(for: arguments.folder ?? .home))
            }
        } catch {
            return ToolReply.failure(error)
        }
    }

    /// Opening an app, script or installer would run code the user never explicitly approved,
    /// so those are only revealed in Finder.
    @MainActor
    private func open(_ url: URL) -> String {
        if Self.isExecutable(url) {
            NSWorkspace.shared.activateFileViewerSelecting([url])
            return String(localized: "\(url.lastPathComponent) çalıştırılabilir bir dosya; güvenlik için açmadım, Finder'da gösterdim.")
        }
        return NSWorkspace.shared.open(url)
            ? String(localized: "\(url.lastPathComponent) açıldı.")
            : ToolReply.failure(String(localized: "\(url.lastPathComponent) açılamadı."))
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

    /// Any file when `extensions` is empty.
    private static func latestFile(in directory: URL, extensions: Set<String>) throws -> URL? {
        let items = try FileManager.default.contentsOfDirectory(
            at: directory, includingPropertiesForKeys: [.contentModificationDateKey], options: .skipsHiddenFiles)
        return FileSearch.sortedByRecency(items).first { extensions.isEmpty || extensions.contains($0.pathExtension.lowercased()) }
    }
}
