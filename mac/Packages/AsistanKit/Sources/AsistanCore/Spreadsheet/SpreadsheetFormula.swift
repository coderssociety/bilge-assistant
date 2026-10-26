/// Checks a formula written by the language model before it goes into a cell. Formulas can reach
/// outside the sheet (fetch a URL, run a program, read another file), and text the model saw could
/// steer what it writes, so only plain calculation is let through.
public enum SpreadsheetFormula {
    public static let maxLength = 300
    /// Network, programs, other files and links.
    private static let blockedFunctions = [
        "WEBSERVICE", "FILTERXML", "HYPERLINK", "CALL", "REGISTER", "EXEC", "RTD", "IMAGE", "INFO", "CELL",
        "INDIRECT", "DDE",
    ]
    private static let allowedSymbols = Set("+-*/^():,;.%<>=&$! \"")

    public static func isSafe(_ formula: String) -> Bool {
        guard formula.hasPrefix("="), formula.count > 1, formula.count <= maxLength else { return false }
        guard formula.allSatisfy({ ($0.isASCII && ($0.isLetter || $0.isNumber)) || allowedSymbols.contains($0) }) else {
            return false
        }
        let upper = formula.uppercased()
        return !blockedFunctions.contains { upper.contains($0 + "(") }
    }
}
