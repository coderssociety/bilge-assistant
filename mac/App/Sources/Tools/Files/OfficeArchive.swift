import AsistanCore
import Foundation

enum OfficeArchiveError: LocalizedError {
    case unreadable(String)

    var errorDescription: String? {
        switch self {
        case let .unreadable(name): String(localized: "'\(name)' açılamadı; dosya bozuk ya da parola korumalı olabilir.")
        }
    }
}

/// Excel, PowerPoint and OpenDocument files are zip archives of XML parts; the parts are taken out with the system's
/// `unzip` and their text is read by `OfficeDocumentText`.
enum OfficeArchive {
    private static let unzip = "/usr/bin/unzip"
    /// A part larger than this is not a document anyone reads out.
    private static let maxPartCharacters = 20_000_000

    static func text(of file: URL, kind: OfficeDocumentText.Kind) async throws -> String {
        let names = try await listing(of: file)
        let parts = OfficeDocumentText.parts(of: kind, in: names)
        guard !parts.isEmpty else { throw OfficeArchiveError.unreadable(file.lastPathComponent) }
        do {
            switch kind {
            case .xlsx:
                let shared = names.contains(OfficeDocumentText.sharedStringsPart)
                    ? try OfficeDocumentText.sharedStrings(await part(OfficeDocumentText.sharedStringsPart, of: file)) : []
                var sheets: [String] = []
                for name in parts { sheets.append(try OfficeDocumentText.sheet(await part(name, of: file), shared: shared)) }
                return sheets.filter { !$0.isEmpty }.joined(separator: "\n\n")
            case .pptx:
                var slides: [String] = []
                for name in parts { slides.append(try OfficeDocumentText.slide(await part(name, of: file))) }
                return slides.filter { !$0.isEmpty }.joined(separator: "\n\n")
            case .ods, .odp:
                return try OfficeDocumentText.openDocument(await part("content.xml", of: file))
            }
        } catch let error as OfficeDocumentText.ReadError {
            Log.tools.error("Office part unreadable: \(String(describing: error), privacy: .public)")
            throw OfficeArchiveError.unreadable(file.lastPathComponent)
        }
    }

    private static func listing(of file: URL) async throws -> [String] {
        let output = try await ProcessRunner.run(unzip, ["-Z1", file.path])
        guard output.status == 0 else { throw OfficeArchiveError.unreadable(file.lastPathComponent) }
        return output.standardOutput.split(whereSeparator: \.isNewline).map(String.init)
    }

    private static func part(_ name: String, of file: URL) async throws -> Data {
        // "-p" writes the part to standard output; the name comes from the archive's own listing.
        let output = try await ProcessRunner.run(unzip, ["-p", file.path, name])
        guard output.status == 0, output.standardOutput.count <= maxPartCharacters else {
            throw OfficeArchiveError.unreadable(file.lastPathComponent)
        }
        return Data(output.standardOutput.utf8)
    }
}
