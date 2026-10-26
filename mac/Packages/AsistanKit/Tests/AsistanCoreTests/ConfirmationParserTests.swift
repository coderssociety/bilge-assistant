import Testing
@testable import AsistanCore

@Suite("ConfirmationParser")
struct ConfirmationParserTests {
    @Test("recognizes approvals", arguments: [
        "Evet", "evet lütfen", "Olur.", "tamam", "onaylıyorum", "Gönder", "yap", "tabii ki", "aynen öyle", "evet evet",
    ])
    func yes(text: String) {
        #expect(ConfirmationParser.parse(text) == .confirmed)
    }

    @Test("recognizes refusals", arguments: [
        "Hayır", "hayır yapma", "iptal", "vazgeç", "Yok.", "istemiyorum", "dur", "gönderme", "silme", "boş ver",
    ])
    func no(text: String) {
        #expect(ConfirmationParser.parse(text) == .rejected)
    }

    @Test("anything unclear or contradictory is unclear", arguments: [
        "", "bilmiyorum", "evet ama hayır", "saat kaç", "belki",
    ])
    func unclear(text: String) {
        #expect(ConfirmationParser.parse(text) == .unclear)
    }
}
