import Testing
@testable import AsistanCore

@Suite("ScriptErrorOutput")
struct ScriptErrorOutputTests {
    @Test("parses an execution error with its code")
    func executionError() {
        let parsed = ScriptErrorOutput.parse("33:44: execution error: nosuchthing değişkeni tanımlanmamış. (-2753)\n")
        #expect(parsed == ScriptErrorOutput(kind: .execution, code: -2753, message: "nosuchthing değişkeni tanımlanmamış."))
    }

    @Test("parses a syntax error")
    func syntaxError() {
        let parsed = ScriptErrorOutput.parse("0:4: syntax error: Expected end of line but found end of script. (-2741)")
        #expect(parsed?.kind == .syntax)
        #expect(parsed?.code == -2741)
    }

    @Test("uses the last error line when warnings come first")
    func lastLine() {
        let output = "osascript: OpenScripting.framework - scripting addition warning\n12:30: execution error: Not authorized to send Apple events to Music. (-1743)"
        #expect(ScriptErrorOutput.parse(output)?.code == -1743)
    }

    @Test("keeps parentheses inside the message")
    func parenthesesInMessage() {
        let parsed = ScriptErrorOutput.parse("1:2: execution error: Music got an error: Can’t get playlist \"Yaz (2024)\". (-1728)")
        #expect(parsed?.message == "Music got an error: Can’t get playlist \"Yaz (2024)\".")
        #expect(parsed?.code == -1728)
    }

    @Test("rejects output that is not an osascript error", arguments: ["", "Killed: 9", "execution error without a code"])
    func rejected(output: String) {
        #expect(ScriptErrorOutput.parse(output) == nil)
    }
}
