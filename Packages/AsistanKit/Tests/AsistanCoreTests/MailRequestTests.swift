import AsistanCore
import Testing

@Suite("MailRequest")
struct MailRequestTests {
    @Test("reading the messages themselves, or only counting them", arguments: [
        ("Maillerimi oku", true), ("E-postalarımı okuyabilir misin", true), ("İçeriklerini oku", true),
        ("E-postanın içeriğini oku", true), ("Ne yazıyor", true), ("Google ne yazmış", true), ("özetle", true),
        ("Read my email", true), ("What does it say?", true),
        ("Kaç mailim var", false), ("Yeni e-posta var mı", false), ("Any new mail?", false),
    ])
    func content(command: String, wantsContent: Bool) {
        #expect(MailRequest.asksForContent(command) == wantsContent)
    }
}
