import AppKit
import FoundationModels
import PDFKit

struct CreateFolderTool: AssistantTool {
    let name = "createFolder"
    let description = "Masaüstünde, Belgeler'de ya da İndirilenler'de adı verilen yeni bir klasör oluşturur."

    @Generable
    enum Location {
        case desktop, documents, downloads
    }

    @Generable
    struct Arguments {
        @Guide(description: "Klasörün adı")
        var name: String
        @Guide(description: "Belirtilmediyse desktop")
        var location: Location
    }

    func call(arguments: Arguments) async throws -> String {
        let name = arguments.name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !name.isEmpty, !name.hasPrefix("."), !name.contains("/"), !name.contains(":") else {
            return ToolReply.failure("Bu adla klasör oluşturamam.")
        }
        let (parent, place): (URL, String) = switch arguments.location {
        case .desktop: (.desktopDirectory, "Masaüstü'nde")
        case .documents: (.documentsDirectory, "Belgeler'de")
        case .downloads: (.downloadsDirectory, "İndirilenler'de")
        }
        let folder = parent.appending(path: name, directoryHint: .isDirectory)
        guard !FileManager.default.fileExists(atPath: folder.path(percentEncoded: false)) else {
            return "\(place) '\(name)' adında bir klasör zaten var."
        }
        do {
            try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: false)
            return "\(place) '\(name)' klasörünü oluşturdum."
        } catch {
            return ToolReply.failure(error)
        }
    }
}

/// "Şu PDF'i özetle", "son indirdiğim belgede ne yazıyor". The text is untrusted and is only
/// answered by the tool-less session.
struct ReadDocumentTool: AssistantTool {
    let name = "readDocument"
    let description = "Bir belgeyi (PDF, metin, Word, RTF) açmadan okur; özetler ya da içeriğiyle ilgili soruyu yanıtlar."
    let answersWithLanguageModel = true
    private static let maxCharacters = 6000
    private static let readableExtensions: Set<String> = ["pdf", "txt", "md", "rtf", "rtfd", "docx", "doc", "html", "htm", "csv"]

    @Generable
    struct Arguments {
        @Guide(description: "Belge adında geçen kelimeler; 'son indirdiğim belge' gibi isteklerde boş bırak")
        var query: String?
    }

    func call(arguments: Arguments) async throws -> String {
        do {
            guard let file = try await Self.locate(arguments.query) else {
                return ToolReply.failure(arguments.query.map { "'\($0)' adında okunabilir bir belge bulamadım." }
                    ?? "İndirilenler'de okunabilir bir belge bulamadım.")
            }
            let text = try Self.text(of: file).trimmingCharacters(in: .whitespacesAndNewlines)
            guard !text.isEmpty else { return ToolReply.failure("'\(file.lastPathComponent)' içinde okunabilir yazı yok.") }
            return "Belge: \(file.lastPathComponent)\n\(text.prefix(Self.maxCharacters))"
        } catch {
            return ToolReply.failure(error)
        }
    }

    private static func locate(_ query: String?) async throws -> URL? {
        if let query, !query.trimmingCharacters(in: .whitespaces).isEmpty {
            return try await FileSearch.find(query, limit: 20).first { readableExtensions.contains($0.pathExtension.lowercased()) }
        }
        let downloads = (try? FileManager.default.contentsOfDirectory(at: .downloadsDirectory, includingPropertiesForKeys: nil)) ?? []
        return FileSearch.sortedByRecency(downloads).first { readableExtensions.contains($0.pathExtension.lowercased()) }
    }

    private static func text(of file: URL) throws -> String {
        switch file.pathExtension.lowercased() {
        case "pdf":
            return PDFDocument(url: file)?.string ?? ""
        case "txt", "md", "csv":
            return try String(contentsOf: file, encoding: .utf8)
        default:
            return try NSAttributedString(url: file, options: [:], documentAttributes: nil).string
        }
    }
}
