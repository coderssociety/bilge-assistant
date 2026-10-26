import AsistanCore
import Foundation
import Observation

enum RoutineStoreError: LocalizedError {
    case notSaved
    case tooMany

    var errorDescription: String? {
        switch self {
        case .notSaved: String(localized: "Rutinleri kaydedemedim.")
        case .tooMany: String(localized: "En çok \(RoutineStore.maxRoutines) rutin kurulabilir; önce birini sil.")
        }
    }
}

/// The routines set up by voice, kept in one JSON file on this Mac only
/// (~/Library/Application Support/Asistan/routines.json, readable by the user alone).
@MainActor
@Observable
final class RoutineStore {
    nonisolated static let maxRoutines = 50

    private struct File: Codable {
        var routines: [Routine]
    }

    /// In the order they are listed and spoken.
    private(set) var routines: [Routine]
    private let fileURL: URL?

    init(fileURL: URL? = RoutineStore.defaultFileURL()) {
        self.fileURL = fileURL
        routines = RoutineSchedule.sorted(Self.load(from: fileURL))
    }

    func add(_ routine: Routine) throws {
        guard routines.count < Self.maxRoutines else { throw RoutineStoreError.tooMany }
        try replace(with: routines + [routine])
    }

    /// The number removed.
    @discardableResult
    func remove(_ ids: Set<UUID>) throws -> Int {
        let kept = routines.filter { !ids.contains($0.id) }
        let removed = routines.count - kept.count
        if removed > 0 { try replace(with: kept) }
        return removed
    }

    /// The file is written first: the assistant must never say it set up a routine the disk lacks.
    private func replace(with updated: [Routine]) throws {
        let sorted = RoutineSchedule.sorted(updated)
        if let fileURL {
            do {
                try PrivateFile.write(try JSONEncoder().encode(File(routines: sorted)), to: fileURL)
            } catch {
                Log.brain.error("Could not save routines: \(error.localizedDescription, privacy: .public)")
                throw RoutineStoreError.notSaved
            }
        }
        routines = sorted
    }

    /// An unreadable file is set aside rather than overwritten by the next routine, so nothing is lost silently.
    private static func load(from url: URL?) -> [Routine] {
        guard let url, FileManager.default.fileExists(atPath: url.path) else { return [] }
        do {
            return try JSONDecoder().decode(File.self, from: Data(contentsOf: url)).routines
        } catch {
            let stamp = Int(Date.now.timeIntervalSince1970)
            let aside = url.deletingPathExtension().appendingPathExtension("corrupt-\(stamp).json")
            try? FileManager.default.moveItem(at: url, to: aside)
            Log.brain.error("Routines file unreadable, moved to \(aside.lastPathComponent, privacy: .public): \(error.localizedDescription, privacy: .public)")
            return []
        }
    }

    private static func defaultFileURL() -> URL? {
        do {
            return try ModelStorage.root().appending(path: "routines.json")
        } catch {
            Log.brain.error("No storage for routines: \(error.localizedDescription, privacy: .public)")
            return nil
        }
    }
}
