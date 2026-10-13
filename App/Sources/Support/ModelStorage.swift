import Foundation

/// App data lives under ~/Library/Application Support/Asistan so it survives rebuilds and never lands in Documents.
enum ModelStorage {
    static func root() throws -> URL {
        let url = try FileManager.default
            .url(for: .applicationSupportDirectory, in: .userDomainMask, appropriateFor: nil, create: true)
            .appending(path: "Asistan", directoryHint: .isDirectory)
        try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        return url
    }

    static func directory(for component: String) throws -> URL {
        let url = try root().appending(path: "Models/\(component)", directoryHint: .isDirectory)
        try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        return url
    }
}
