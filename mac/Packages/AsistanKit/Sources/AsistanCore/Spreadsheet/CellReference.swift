/// An A1-style cell address such as "D3" or "AA12", within Excel's limits (XFD1048576).
public struct CellReference: Equatable, Hashable, Sendable {
    public let column: String
    public let row: Int

    private static let maxColumn = 16_384
    private static let maxRow = 1_048_576

    public init?(_ text: String) {
        let upper = text.uppercased()
        let letters = upper.prefix { $0.isASCII && $0.isLetter }
        let digits = upper.dropFirst(letters.count)
        guard (1...3).contains(letters.count), !digits.isEmpty, digits.allSatisfy(\.isASCII), let row = Int(digits),
              (1...Self.maxRow).contains(row), Self.columnNumber(String(letters)) <= Self.maxColumn
        else { return nil }
        column = String(letters)
        self.row = row
    }

    public var address: String { "\(column)\(row)" }

    private static func columnNumber(_ letters: String) -> Int {
        letters.unicodeScalars.reduce(0) { $0 * 26 + Int($1.value) - 64 }
    }
}

public enum SpreadsheetValue: Equatable, Sendable {
    case number(Double)
    case text(String)
}
