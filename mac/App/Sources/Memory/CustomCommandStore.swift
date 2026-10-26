import AsistanCore
import Foundation
import Observation

enum CustomCommandStoreError: LocalizedError {
    case notSaved

    var errorDescription: String? {
        String(localized: "Komutları kaydedemedim.")
    }
}

/// The user's own commands and which of them were already run with a spoken yes, kept in one JSON file on this Mac
/// only (~/Library/Application Support/Asistan/commands.json, readable by the user alone). An approval is bound to
/// the command's fingerprint, so editing a command asks again.
@MainActor
@Observable
final class CustomCommandStore {
    private struct File: Codable {
        var commands: [CustomCommand]
        var approved: [String]
    }

    private(set) var commands: [CustomCommand]
    private var approved: Set<String>
    private let fileURL: URL?

    init(fileURL: URL? = CustomCommandStore.defaultFileURL()) {
        self.fileURL = fileURL
        let file = Self.load(from: fileURL)
        commands = file.commands
        approved = Set(file.approved)
    }

    func find(_ spoken: String) -> CustomCommand? {
        guard let name = CustomCommandRequest.bestMatch(spoken, in: commands.map(\.name)) else { return nil }
        return commands.first { $0.name == name }
    }

    func isApproved(_ command: CustomCommand) -> Bool {
        approved.contains(command.fingerprint)
    }

    func approve(_ command: CustomCommand) throws {
        try save(commands: commands, approved: approved.union([command.fingerprint]))
    }

    /// Approvals of commands no longer in the list are dropped with them.
    func replace(with updated: [CustomCommand]) throws {
        let kept = approved.intersection(updated.map(\.fingerprint))
        try save(commands: updated, approved: kept)
    }

    /// The file is written first: the assistant must never act on a command the disk lacks.
    private func save(commands updated: [CustomCommand], approved updatedApprovals: Set<String>) throws {
        if let fileURL {
            do {
                try PrivateFile.write(try JSONEncoder().encode(File(commands: updated, approved: updatedApprovals.sorted())), to: fileURL)
            } catch {
                Log.brain.error("Could not save commands: \(error.localizedDescription, privacy: .public)")
                throw CustomCommandStoreError.notSaved
            }
        }
        commands = updated
        approved = updatedApprovals
    }

    /// An unreadable file is set aside rather than overwritten by the next save, so nothing is lost silently.
    private static func load(from url: URL?) -> File {
        let empty = File(commands: [], approved: [])
        guard let url, FileManager.default.fileExists(atPath: url.path) else { return empty }
        do {
            return try JSONDecoder().decode(File.self, from: Data(contentsOf: url))
        } catch {
            let stamp = Int(Date.now.timeIntervalSince1970)
            let aside = url.deletingPathExtension().appendingPathExtension("corrupt-\(stamp).json")
            try? FileManager.default.moveItem(at: url, to: aside)
            Log.brain.error("Commands file unreadable, moved to \(aside.lastPathComponent, privacy: .public): \(error.localizedDescription, privacy: .public)")
            return empty
        }
    }

    private static func defaultFileURL() -> URL? {
        do {
            return try ModelStorage.root().appending(path: "commands.json")
        } catch {
            Log.brain.error("No storage for commands: \(error.localizedDescription, privacy: .public)")
            return nil
        }
    }
}
