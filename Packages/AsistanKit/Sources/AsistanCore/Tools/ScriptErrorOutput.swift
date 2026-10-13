/// The error line `osascript` writes to standard error, e.g.
/// "33:44: execution error: Not authorized to send Apple events to Music. (-1743)".
public struct ScriptErrorOutput: Equatable, Sendable {
    public enum Kind: Sendable {
        case syntax, execution
    }

    public let kind: Kind
    public let code: Int
    public let message: String

    public init(kind: Kind, code: Int, message: String) {
        self.kind = kind
        self.code = code
        self.message = message
    }

    public static func parse(_ standardError: String) -> ScriptErrorOutput? {
        let line = standardError.split(whereSeparator: \.isNewline).last.map(String.init) ?? ""
        let pattern = /^(?:\d+:\d+: )?(?<kind>syntax|execution) error: (?<message>.*) \((?<code>-?\d+)\)$/
        guard let match = line.wholeMatch(of: pattern), let code = Int(match.code) else { return nil }
        return ScriptErrorOutput(kind: match.kind == "syntax" ? .syntax : .execution, code: code, message: String(match.message))
    }
}
