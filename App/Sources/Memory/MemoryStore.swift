import AsistanCore
import Foundation
import Observation

enum MemoryStoreError: LocalizedError {
    case notSaved

    var errorDescription: String? { "Hafızaya kaydedemedim." }
}

/// The facts the user asked the assistant to remember, kept in one JSON file on this Mac only
/// (~/Library/Application Support/Asistan/memory.json, readable by the user alone).
@MainActor
@Observable
final class MemoryStore {
    /// Budget for the facts inside the conversation instructions; the on-device model has an 8K window.
    static let promptCharacters = 1500

    private(set) var book: MemoryBook
    /// Bumped on every change, so cached conversation sessions know their instructions are stale.
    private(set) var revision = 0
    private let fileURL: URL?

    init(fileURL: URL? = MemoryStore.defaultFileURL()) {
        self.fileURL = fileURL
        book = Self.load(from: fileURL)
    }

    var promptLines: String? { book.promptLines(maxCharacters: Self.promptCharacters) }

    func remember(_ fact: String) throws -> MemoryBook.AddOutcome {
        let (updated, outcome) = book.adding(fact, at: .now)
        if outcome == .added || outcome == .addedDroppingOldest { try replace(with: updated) }
        return outcome
    }

    func entry(matching query: String) -> MemoryEntry? {
        book.entry(matching: query)
    }

    func forget(id: UUID) throws {
        try replace(with: book.removing(id: id))
    }

    func forgetAll() throws -> Int {
        let count = book.entries.count
        if count > 0 { try replace(with: MemoryBook()) }
        return count
    }

    /// The file is written first: the assistant must never say it remembered something the disk lacks.
    private func replace(with updated: MemoryBook) throws {
        try save(updated)
        book = updated
        revision += 1
    }

    private func save(_ book: MemoryBook) throws {
        guard let fileURL else { return }
        do {
            try PrivateFile.write(try JSONEncoder().encode(book), to: fileURL)
        } catch {
            Log.brain.error("Could not save memory: \(error.localizedDescription, privacy: .public)")
            throw MemoryStoreError.notSaved
        }
    }

    /// An unreadable file is set aside rather than overwritten by the next fact, so nothing is lost silently.
    private static func load(from url: URL?) -> MemoryBook {
        guard let url, FileManager.default.fileExists(atPath: url.path) else { return MemoryBook() }
        do {
            return try JSONDecoder().decode(MemoryBook.self, from: Data(contentsOf: url))
        } catch {
            let stamp = Int(Date.now.timeIntervalSince1970)
            let aside = url.deletingPathExtension().appendingPathExtension("corrupt-\(stamp).json")
            try? FileManager.default.moveItem(at: url, to: aside)
            Log.brain.error("Memory file unreadable, moved to \(aside.lastPathComponent, privacy: .public): \(error.localizedDescription, privacy: .public)")
            return MemoryBook()
        }
    }

    private static func defaultFileURL() -> URL? {
        do {
            return try ModelStorage.root().appending(path: "memory.json")
        } catch {
            Log.brain.error("No storage for memory: \(error.localizedDescription, privacy: .public)")
            return nil
        }
    }
}
