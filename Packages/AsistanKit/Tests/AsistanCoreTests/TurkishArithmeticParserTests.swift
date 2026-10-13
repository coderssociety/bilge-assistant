import Testing
@testable import AsistanCore

@Suite("TurkishArithmeticParser")
struct TurkishArithmeticParserTests {
    @Test("turns common spoken arithmetic into an expression", arguments: [
        ("125'in %18'i kaç eder", "125 * 18 / 100"),
        ("125'in yüzde 18'i ne kadar", "125 * 18 / 100"),
        ("1200'ün yüzde 20'si", "1200 * 20 / 100"),
        ("120'nin yarısı kaç", "120 / 2"),
        ("320'nin çeyreği", "320 / 4"),
        ("90'ın üçte biri", "90 / 3"),
        ("865 × 254", "865 * 254"),
        ("12 çarpı 15", "12 * 15"),
        ("600 bölü 4 kaç eder", "600 / 4"),
        ("45 artı 17 eksi 3", "45 + 17 - 3"),
        ("2'nin 10. kuvveti", "2 ^ 10"),
        ("3,5 kere 2 hesapla", "3,5 * 2"),
    ])
    func parses(command: String, expected: String) {
        #expect(TurkishArithmeticParser.expression(from: command) == expected)
    }

    @Test("returns nil for text that is not plain arithmetic", arguments: [
        "Evet", "%20'nin yarısı kaç", "Safari'yi aç", "kaç tane alarm var", "",
    ])
    func rejects(command: String) {
        #expect(TurkishArithmeticParser.expression(from: command) == nil)
    }

    @Test("an expression is grounded only if its numbers were said", arguments: [
        ("125 * 18 / 100", "125'in %18'i", true),
        ("120 / 2", "120'nin yarısı", true),
        ("125 * 18 / 100", "Evet", false),
        ("20 * 5 / 100", "%20'nin yarısı kaç", false),
        ("600 / 4", "600 bölü 4", true),
    ])
    func grounding(expression: String, command: String, grounded: Bool) {
        #expect(TurkishArithmeticParser.isGrounded(expression, in: command) == grounded)
    }
}
