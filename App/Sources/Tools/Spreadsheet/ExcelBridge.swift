import AppKit
import AsistanCore

enum SpreadsheetError: LocalizedError {
    case rangeTooLarge

    var errorDescription: String? { String(localized: "Bu aralık sesle hesaplamak için çok büyük.") }
}

/// Microsoft Excel through AppleScript. Cell addresses are validated `CellReference`s; every other
/// piece of text (workbook and sheet names, formulas, values) goes in through `quoted(_:)`.
enum ExcelBridge {
    static let bundleIdentifier = "com.microsoft.Excel"
    private static let application = "tell application \"Microsoft Excel\""

    /// Where a change was made, so undo writes back into the same sheet even if another one is in front.
    struct Location: Equatable, Sendable {
        let workbook: String
        let sheet: String
    }

    /// Asked of AppleScript rather than NSRunningApplication, whose list lagged behind in testing;
    /// "is running" never launches Excel.
    static func isRunning() async -> Bool {
        (try? await AppleScriptRunner.run("return application id \"\(bundleIdentifier)\" is running")) == "true"
    }

    /// The sheet in front, or nil when no workbook is open.
    static func activeLocation() async throws -> Location? {
        let output = try await AppleScriptRunner.run("""
        \(application)
        if (count of workbooks) = 0 then return ""
        return (name of active workbook) & linefeed & (name of active sheet)
        end tell
        """)
        let parts = output.split(separator: "\n", maxSplits: 1).map(String.init)
        return parts.count == 2 ? Location(workbook: parts[0], sheet: parts[1]) : nil
    }

    /// The cell's formula, or its constant as text; empty for an empty cell.
    static func formula(of cell: CellReference, at location: Location) async throws -> String {
        try await AppleScriptRunner.run("\(application) to return formula of \(range(cell, location))")
    }

    /// What the cell shows, formatted as in the sheet ("1.250,50").
    static func displayedValue(of cell: CellReference, at location: Location) async throws -> String {
        try await AppleScriptRunner.run("\(application) to return string value of \(range(cell, location))")
    }

    static func setFormula(_ formula: String, in cell: CellReference, at location: Location) async throws {
        _ = try await AppleScriptRunner.run(
            "\(application) to set formula of \(range(cell, location)) to \(AppleScriptRunner.quoted(formula))")
    }

    static func setValue(_ value: SpreadsheetValue, in cell: CellReference, at location: Location) async throws {
        let literal: String
        switch value {
        case let .number(number):
            literal = number.rounded() == number && abs(number) < 1e15 ? String(Int(number)) : String(number)
        case let .text(text):
            // A leading "=", "+", "-" or "@" would make Excel read spoken text as a formula.
            let isFormulaLike = text.first.map { "=+-@".contains($0) } ?? false
            literal = AppleScriptRunner.quoted(isFormulaLike ? "'" + text : text)
        }
        _ = try await AppleScriptRunner.run("\(application) to set value of \(range(cell, location)) to \(literal)")
    }

    static func clear(_ cell: CellReference, at location: Location) async throws {
        _ = try await AppleScriptRunner.run("\(application) to clear contents \(range(cell, location))")
    }

    static func copy(_ source: CellReference, to destination: CellReference, at location: Location) async throws {
        _ = try await AppleScriptRunner.run(
            "\(application) to copy range \(range(source, location)) destination \(range(destination, location))")
    }

    /// Larger ranges are refused rather than read cell by cell.
    static let maxCells = 10_000

    /// The values of a cell or range ("B1:B9", "C:C"), one text per cell. A whole column is cut to the
    /// rows in use.
    static func values(of reference: String, at location: Location) async throws -> [String] {
        let sheet = "worksheet \(AppleScriptRunner.quoted(location.sheet)) of workbook \(AppleScriptRunner.quoted(location.workbook))"
        var address = reference
        if !reference.contains(where: \.isNumber) {
            let lastRow = try await AppleScriptRunner.run("""
            \(application)
            set usedCells to used range of \(sheet)
            return (first row index of usedCells) + (count of rows of usedCells) - 1
            end tell
            """)
            let columns = reference.split(separator: ":").map(String.init)
            guard columns.count == 2, let rows = Int(lastRow), rows <= maxCells else { throw SpreadsheetError.rangeTooLarge }
            address = "\(columns[0])1:\(columns[1])\(rows)"
        }
        let output = try await AppleScriptRunner.run("""
        \(application)
        set found to value of range \(AppleScriptRunner.quoted(address)) of \(sheet)
        set out to {}
        if class of found is list then
            repeat with rowValues in found
                if class of rowValues is list then
                    repeat with cellValue in rowValues
                        set end of out to (cellValue as text)
                    end repeat
                else
                    set end of out to (rowValues as text)
                end if
            end repeat
        else
            set end of out to (found as text)
        end if
        set AppleScript's text item delimiters to linefeed
        return out as text
        end tell
        """)
        let values = output.components(separatedBy: "\n")
        guard values.count <= maxCells else { throw SpreadsheetError.rangeTooLarge }
        return values
    }

    private static func range(_ cell: CellReference, _ location: Location) -> String {
        "range \"\(cell.address)\" of worksheet \(AppleScriptRunner.quoted(location.sheet)) of workbook \(AppleScriptRunner.quoted(location.workbook))"
    }
}
