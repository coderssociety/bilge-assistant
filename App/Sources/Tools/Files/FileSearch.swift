import Foundation

/// Spotlight lookup restricted to the user's home folder, newest first.
enum FileSearch {
    static func find(_ query: String, limit: Int) async throws -> [URL] {
        let home = FileManager.default.homeDirectoryForCurrentUser.path
        let output = try await ProcessRunner.run("/usr/bin/mdfind", ["-onlyin", home, "-name", query])
        let urls = output.standardOutput.split(separator: "\n").map { URL(filePath: String($0)) }
            .filter { !$0.path.contains("/Library/") && !$0.lastPathComponent.hasPrefix(".") }
        return Array(sortedByRecency(urls).prefix(limit))
    }

    static func sortedByRecency(_ urls: [URL]) -> [URL] {
        urls.map { ($0, (try? $0.resourceValues(forKeys: [.contentModificationDateKey]))?.contentModificationDate ?? .distantPast) }
            .sorted { $0.1 > $1.1 }
            .map(\.0)
    }

    static func describeLocation(_ url: URL) -> String {
        url.deletingLastPathComponent().path.replacingOccurrences(of: NSHomeDirectory(), with: "~")
    }
}
