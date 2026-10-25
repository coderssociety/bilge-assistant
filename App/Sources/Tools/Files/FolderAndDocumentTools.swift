import AsistanCore
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
            return ToolReply.failure(String(localized: "Bu adla klasör oluşturamam."))
        }
        let (parent, place): (URL, String) = switch arguments.location {
        case .desktop: (.desktopDirectory, String(localized: "Masaüstü'nde"))
        case .documents: (.documentsDirectory, String(localized: "Belgeler'de"))
        case .downloads: (.downloadsDirectory, String(localized: "İndirilenler'de"))
        }
        let folder = parent.appending(path: name, directoryHint: .isDirectory)
        guard !FileManager.default.fileExists(atPath: folder.path(percentEncoded: false)) else {
            return String(localized: "\(place) '\(name)' adında bir klasör zaten var.")
        }
        do {
            try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: false)
            return String(localized: "\(place) '\(name)' klasörünü oluşturdum.")
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
    let readingLayout: ContinuedReading.Layout? = .text(maxCharacters: 6000)
    static let readableExtensions: Set<String> = ["pdf", "txt", "md", "rtf", "rtfd", "docx", "doc", "html", "htm", "csv"]

    @Generable
    struct Arguments {
        @Guide(description: "Belge adında geçen kelimeler. 'Son indirdiğim PDF' gibi isteklerde yalnızca türü yaz ('pdf', 'word'); tür de yoksa boş bırak")
        var query: String?
    }

    func call(arguments: Arguments) async throws -> String {
        do {
            guard let file = try await Self.locate(arguments.query) else {
                return ToolReply.failure(arguments.query.map { String(localized: "'\($0)' adında okunabilir bir belge bulamadım.") }
                    ?? String(localized: "İndirilenler'de okunabilir bir belge bulamadım."))
            }
            let text = try await Self.text(of: file).trimmingCharacters(in: .whitespacesAndNewlines)
            guard !text.isEmpty else {
                return ToolReply.failure(String(localized: "'\(file.lastPathComponent)' içinde okunabilir yazı yok."))
            }
            return String(localized: "Belge: \(file.lastPathComponent)\n\(text)")
        } catch {
            return ToolReply.failure(error)
        }
    }

    private static let typeWords: [String: Set<String>] = [
        "pdf": ["pdf"], "word": ["docx", "doc"], "metin": ["txt", "md", "rtf"], "tablo": ["csv"],
    ]

    /// A name search first. Phrasings like "son indirilen PDF" name no file, so they fall back to the
    /// newest download of the mentioned type (or of any readable type).
    private static func locate(_ query: String?) async throws -> URL? {
        let query = query?.trimmingCharacters(in: .whitespaces) ?? ""
        if !query.isEmpty,
           let found = try await FileSearch.find(query, limit: 20).first(where: { readableExtensions.contains($0.pathExtension.lowercased()) }) {
            return found
        }
        let words = TurkishText.folded(query).split(separator: " ").map(String.init)
        let wanted = words.compactMap { word in typeWords.first { word.hasPrefix($0.key) }?.value }.reduce(Set<String>()) { $0.union($1) }
        let mentionsDownload = words.contains { $0.hasPrefix("indir") || $0 == "son" }
        guard query.isEmpty || !wanted.isEmpty || mentionsDownload else { return nil }
        let extensions = wanted.isEmpty ? readableExtensions : wanted
        let downloads = (try? FileManager.default.contentsOfDirectory(at: .downloadsDirectory, includingPropertiesForKeys: nil)) ?? []
        return FileSearch.sortedByRecency(downloads).first { extensions.contains($0.pathExtension.lowercased()) }
    }

    static func text(of file: URL) async throws -> String {
        switch file.pathExtension.lowercased() {
        case "pdf":
            guard let document = PDFDocument(url: file) else { return "" }
            let text = document.string ?? ""
            return text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? try await scannedText(of: document) : text
        case "txt", "md", "csv":
            return try String(contentsOf: file, encoding: .utf8)
        default:
            return try NSAttributedString(url: file, options: [:], documentAttributes: nil).string
        }
    }

    private static let scannedPages = 5
    /// Points to pixels: enough for small print.
    private static let scanScale: CGFloat = 2

    /// A scan has no text layer; its first pages are read like the screen.
    private static func scannedText(of document: PDFDocument) async throws -> String {
        var pages: [String] = []
        for index in 0..<min(document.pageCount, scannedPages) {
            guard let page = document.page(at: index) else { continue }
            let size = page.bounds(for: .mediaBox).size
            let picture = page.thumbnail(of: CGSize(width: size.width * scanScale, height: size.height * scanScale), for: .mediaBox)
            guard let image = picture.cgImage(forProposedRect: nil, context: nil, hints: nil) else { continue }
            pages.append(try await TextRecognition.text(in: image))
        }
        return pages.joined(separator: "\n\n")
    }
}
