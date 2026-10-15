import Testing
@testable import AsistanCore

@Suite("EnglishArithmeticParser")
struct EnglishArithmeticParserTests {
    @Test("common phrasings", arguments: [
        ("How much is 15 percent of 240", String?.some("240 * 15 / 100")),
        ("What's 15% of 240?", "240 * 15 / 100"),
        ("48 divided by 6", "48 / 6"),
        ("What is 125 times 18", "125 * 18"),
        ("12 multiplied by 4", "12 * 4"),
        ("45 plus 17 minus 3", "45 + 17 - 3"),
        ("half of 80", "80 / 2"),
        ("What's a third of 90?", "90 / 3"),
        ("3 squared", "3 ^ 2"),
        ("2 to the power of 10", "2 ^ 10"),
        ("What is 1,250 plus 3.5", "1250 + 3.5"),
        ("What's the weather", nil),
        ("Call 3 people", nil),
    ])
    func expression(command: String, expected: String?) {
        #expect(EnglishArithmeticParser.expression(from: command) == expected)
    }

    @Test("a model-written expression must use numbers that were said")
    func grounded() {
        #expect(EnglishArithmeticParser.isGrounded("240 * 15 / 100", in: "15 percent of 240"))
        #expect(EnglishArithmeticParser.isGrounded("80 / 2", in: "what's half of 80"))
        #expect(!EnglishArithmeticParser.isGrounded("125 * 18 / 100", in: "yes"))
        #expect(!EnglishArithmeticParser.isGrounded("7 * 9", in: "what's 7 times 8"))
    }

    @Test("results read with a decimal point in English")
    func display() {
        #expect(ArithmeticEvaluator.display(22.5, language: .english) == "22.5")
        #expect(ArithmeticEvaluator.display(22.5) == "22,5")
    }
}
