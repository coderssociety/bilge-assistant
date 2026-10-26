import Testing
@testable import AsistanCore

@Suite("PhraseMatcher")
struct PhraseMatcherTests {
    private let reminders = ["Süt al", "Faturayı öde", "Annemi ara", "Alarm kur"]

    @Test("finds titles from suffixed spoken forms", arguments: [
        ("süt almayı", "Süt al"), ("faturayı ödemeyi", "Faturayı öde"), ("annemi aramayı", "Annemi ara"),
    ])
    func suffixed(query: String, expected: String) {
        #expect(PhraseMatcher.bestMatch(for: query, in: reminders) == expected)
    }

    @Test("a first name finds the full contact name")
    func partialName() {
        #expect(PhraseMatcher.bestMatch(for: "Ahmet", in: ["Ayşe Demir", "Ahmet Yılmaz"]) == "Ahmet Yılmaz")
        #expect(PhraseMatcher.bestMatch(for: "Ahmet'in", in: ["Ayşe Demir", "Ahmet Yılmaz"]) == "Ahmet Yılmaz")
    }

    @Test("prefers the title covering more of the phrase")
    func coverage() {
        #expect(PhraseMatcher.bestMatch(for: "yaz şarkıları", in: ["Yaz", "Yaz Şarkıları", "Kış Şarkıları"]) == "Yaz Şarkıları")
    }

    @Test("returns nil when nothing is close", arguments: ["ekmek", "", "ve"])
    func noMatch(query: String) {
        #expect(PhraseMatcher.bestMatch(for: query, in: reminders) == nil)
    }

    @Test("a whole spoken sentence still finds the reminder", arguments: [
        ("süt almayı tamamladım işaretle", "Süt al"), ("faturayı ödedim listeden düş", "Faturayı öde"),
    ])
    func wholeSentence(query: String, expected: String) {
        #expect(PhraseMatcher.bestMatch(for: query, in: reminders) == expected)
    }
}
