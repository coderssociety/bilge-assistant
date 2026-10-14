import Foundation

/// Answers spreadsheet questions ("B1'den B9'a kadar toplam kaç") from cell values read out of the
/// sheet. Excel's own `evaluate` is not reachable through AppleScript, and nothing is written to work
/// it out. Covers the formulas `SpreadsheetCommand.evaluate` produces.
public enum SpreadsheetEvaluator {
    // Regex values are not Sendable, so they are built where used rather than stored.
    private static var referencePattern: Regex<Substring> { /\$?[A-Z]{1,3}\$?[0-9]*(?::\$?[A-Z]{1,3}\$?[0-9]*)?/ }
    private static var functionPattern: Regex<(Substring, Substring, Substring)> { /^([A-Z]+)\((.*)\)$/ }

    /// The cells and ranges the formula reads, e.g. ["B1:B9"] or ["B2", "B1"].
    public static func references(in formula: String) -> [String] {
        let body = formula.hasPrefix("=") ? String(formula.dropFirst()) : formula
        let arguments = body.wholeMatch(of: functionPattern).map { String($0.2) } ?? body
        var seen: [String] = []
        for match in arguments.matches(of: referencePattern) {
            let reference = String(match.0)
            guard reference.contains(where: \.isNumber) || reference.contains(":"), !seen.contains(reference) else { continue }
            seen.append(reference)
        }
        return seen
    }

    /// `values` holds what was read for each reference, one entry per cell, as text.
    public static func evaluate(_ formula: String, values: [String: [String]]) -> Double? {
        let body = formula.hasPrefix("=") ? String(formula.dropFirst()) : formula
        if let match = body.wholeMatch(of: functionPattern) {
            let numbers = String(match.2).split(separator: ",").flatMap { argument -> [Double] in
                let key = argument.trimmingCharacters(in: .whitespaces)
                if let literal = Double(key) { return [literal] }
                return (values[key] ?? []).compactMap(number)
            }
            return aggregate(String(match.1), numbers)
        }
        var expression = body
        for reference in references(in: body).sorted(by: { $0.count > $1.count }) {
            guard let text = values[reference]?.first else { return nil }
            guard let value = text.isEmpty ? 0 : number(text) else { return nil }
            expression = expression.replacingOccurrences(of: reference, with: "(\(value))")
        }
        return try? ArithmeticEvaluator.evaluate(expression)
    }

    private static func aggregate(_ function: String, _ numbers: [Double]) -> Double? {
        switch function {
        case "SUM": numbers.reduce(0, +)
        case "AVERAGE": numbers.isEmpty ? nil : numbers.reduce(0, +) / Double(numbers.count)
        case "MAX": numbers.max()
        case "MIN": numbers.min()
        case "COUNT": Double(numbers.count)
        default: nil
        }
    }

    /// Cell text as AppleScript gives it: "20.5", or "20,5" where the system uses a decimal comma.
    private static func number(_ text: String) -> Double? {
        let trimmed = text.trimmingCharacters(in: .whitespaces)
        return Double(trimmed) ?? (trimmed.contains(".") ? nil : Double(trimmed.replacingOccurrences(of: ",", with: ".")))
    }
}
