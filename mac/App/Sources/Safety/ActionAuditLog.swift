import Foundation

/// Append-only local record of every action the assistant took or declined, so the user can always
/// see what was done on their Mac. One JSON object per line; never leaves the machine.
actor ActionAuditLog {
    enum Decision: String, Codable, Sendable {
        case executed
        case rejected
        case unconfirmed
    }

    struct Entry: Codable, Sendable {
        let date: Date
        let command: String
        let tool: String
        let arguments: String
        let decision: Decision
        let result: String?
    }

    static let shared = ActionAuditLog()
    private static let maxResultLength = 300

    private let encoder: JSONEncoder = {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        return encoder
    }()

    nonisolated static var fileURL: URL? {
        try? ModelStorage.root().appending(path: "actions.jsonl")
    }

    /// Newest first. Unreadable lines are skipped (and logged) rather than hiding the whole history.
    func recentEntries(limit: Int) -> [Entry] {
        guard let url = Self.fileURL, let data = try? Data(contentsOf: url) else { return [] }
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        let lines = data.split(separator: 0x0A).suffix(limit)
        return lines.reversed().compactMap { line in
            do {
                return try decoder.decode(Entry.self, from: Data(line))
            } catch {
                Log.tools.error("Skipping unreadable audit line: \(error.localizedDescription, privacy: .public)")
                return nil
            }
        }
    }

    func record(command: String, call: PreparedToolCall, decision: Decision, result: String?) {
        let entry = Entry(date: .now, command: command, tool: call.toolName, arguments: call.argumentsDescription,
                          decision: decision, result: result.map { String($0.prefix(Self.maxResultLength)) })
        do {
            guard let url = Self.fileURL else { return }
            var line = try encoder.encode(entry)
            line.append(0x0A)
            if FileManager.default.fileExists(atPath: url.path) {
                let handle = try FileHandle(forWritingTo: url)
                defer { try? handle.close() }
                try handle.seekToEnd()
                try handle.write(contentsOf: line)
            } else {
                try line.write(to: url, options: .atomic)
            }
        } catch {
            Log.tools.error("Audit log write failed: \(error.localizedDescription, privacy: .public)")
        }
    }
}
