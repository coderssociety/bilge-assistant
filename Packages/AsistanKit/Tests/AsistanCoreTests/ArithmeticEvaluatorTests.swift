import Testing
@testable import AsistanCore

@Suite("ArithmeticEvaluator")
struct ArithmeticEvaluatorTests {
    @Test("evaluates with operator precedence and parentheses", arguments: [
        ("1 + 2 * 3", 7.0), ("(1 + 2) * 3", 9.0), ("125 * 18 / 100", 22.5), ("-4 + 10", 6.0),
        ("2 ^ 10", 1024.0), ("3,5 * 2", 7.0), ("10 % 3", 1.0), ("((2))", 2.0), ("2 * -3", -6.0),
    ])
    func evaluates(expression: String, expected: Double) throws {
        #expect(try ArithmeticEvaluator.evaluate(expression) == expected)
    }

    @Test("rejects anything that is not plain arithmetic", arguments: [
        "", "1 +", "(1 + 2", "1 + 2)", "FUNCTION(1, 'exit')", "abc", "1 / 0", "2 ^ 99999",
    ])
    func rejects(expression: String) {
        #expect(throws: ArithmeticEvaluator.EvaluationError.self) { try ArithmeticEvaluator.evaluate(expression) }
    }

    @Test("renders results for Turkish speech")
    func rendering() {
        #expect(ArithmeticEvaluator.display(22.5) == "22,5")
        #expect(ArithmeticEvaluator.display(1024) == "1024")
        #expect(ArithmeticEvaluator.display(1.0 / 3.0) == "0,3333")
    }
}
