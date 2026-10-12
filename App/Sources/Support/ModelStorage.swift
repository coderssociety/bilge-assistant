import Foundation

/// Models live under Application Support so they survive rebuilds and never land in Documents.
enum ModelStorage {
    static func directory(for component: String) throws -> URL {
        let url = try FileManager.default
            .url(for: .applicationSupportDirectory, in: .userDomainMask, appropriateFor: nil, create: true)
            .appending(path: "Asistan/Models/\(component)", directoryHint: .isDirectory)
        try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        return url
    }
}
