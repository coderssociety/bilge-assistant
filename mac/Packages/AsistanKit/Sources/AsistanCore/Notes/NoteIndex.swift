/// The list of notes a Notes script prints: one block of ids, one of names and one of seconds since each
/// note changed, line for line, with the blocks parted by a record separator. Bulk property reads are a
/// single Apple event each, where reading note by note took seconds with many notes.
public enum NoteIndex {
    public struct Entry: Equatable, Sendable {
        public let id: String
        public let name: String
        public let secondsSinceChange: Int

        public init(id: String, name: String, secondsSinceChange: Int) {
            self.id = id
            self.name = name
            self.secondsSinceChange = secondsSinceChange
        }
    }

    public static let blockSeparator = "\u{1E}"

    /// Empty when the blocks do not line up, rather than pairing ids with the wrong names.
    public static func parse(_ output: String) -> [Entry] {
        let blocks = output.components(separatedBy: blockSeparator).map { $0.trimmingCharacters(in: .newlines) }
        guard blocks.count == 3, !blocks[0].isEmpty else { return [] }
        let ids = blocks[0].components(separatedBy: "\n")
        let names = blocks[1].components(separatedBy: "\n")
        let ages = blocks[2].components(separatedBy: "\n").map { Int($0.trimmingCharacters(in: .whitespaces)) }
        guard ids.count == names.count, ids.count == ages.count else { return [] }
        return ids.indices.compactMap { index in
            ages[index].map { Entry(id: ids[index], name: names[index], secondsSinceChange: $0) }
        }
    }

    /// Named notes, most recently changed first.
    public static func recent(_ entries: [Entry], limit: Int) -> [Entry] {
        Array(entries.filter { !$0.name.trimmingCharacters(in: .whitespaces).isEmpty }
            .sorted { $0.secondsSinceChange < $1.secondsSinceChange }
            .prefix(limit))
    }

    /// The note a spoken name refers to; among notes of the same name, the one changed last.
    public static func find(_ spokenName: String, in entries: [Entry]) -> Entry? {
        let byRecency = entries.sorted { $0.secondsSinceChange < $1.secondsSinceChange }
        guard let name = PhraseMatcher.bestMatch(for: spokenName, in: byRecency.map(\.name)) else { return nil }
        return byRecency.first { $0.name == name }
    }
}
