import AsistanCore
import Foundation

/// Hands-free spreadsheet work: whether "Excel mode" is on, and the assistant's own changes so
/// "geri al" can restore them (changes made through scripting do not always enter Excel's undo).
@MainActor
final class SpreadsheetSession {
    struct Change: Sendable {
        let location: ExcelBridge.Location
        let cell: CellReference
        /// The formula or constant the cell held before, empty if it was empty.
        let previous: String
    }

    /// How long Excel mode waits for the next command.
    static let window: TimeInterval = 45
    private static let maxHistory = 30

    private(set) var isActive = false
    private var history: [Change] = []

    var canUndo: Bool { !history.isEmpty }

    func begin() {
        isActive = true
    }

    func end() {
        isActive = false
    }

    func record(_ change: Change) {
        history = Array((history + [change]).suffix(Self.maxHistory))
    }

    func takeLastChange() -> Change? {
        history.popLast()
    }
}
