import Testing
@testable import AsistanCore

@Suite("Note requests")
struct NoteRequestTests {
    @Test("adding to an existing note keeps the user's own words", arguments: [
        ("alışveriş notuma süt ekle", "alışveriş", "süt"),
        ("Toplantı notuna şunu ekle: bütçe onaylandı", "Toplantı", "bütçe onaylandı"),
        ("market notuma 2 ekmek ve süt yazar mısın", "market", "2 ekmek ve süt"),
        ("toplantı notunun sonuna 'bütçe onaylandı' diye ekle", "toplantı", "bütçe onaylandı"),
        ("lütfen tarif notuma bir tutam tuz ekle", "tarif", "bir tutam tuz"),
        ("Proje notlarıma ekle, sunum cuma günü", "Proje", "sunum cuma günü"),
    ])
    func turkishAddition(command: String, note: String, text: String) {
        #expect(NoteRequest.addition(in: command) == NoteRequest.Addition(note: note, text: text))
    }

    @Test("English additions", arguments: [
        ("add milk to my shopping note", "shopping", "milk"),
        ("append the budget is approved to the meeting note", "meeting", "the budget is approved"),
        ("add to my shopping note: eggs and bread", "shopping", "eggs and bread"),
        ("write in my meeting note that the demo moved to Friday", "meeting", "the demo moved to Friday"),
    ])
    func englishAddition(command: String, note: String, text: String) {
        #expect(NoteRequest.addition(in: command, language: .english) == NoteRequest.Addition(note: note, text: text))
    }

    @Test("not an addition to a named note", arguments: [
        "toplantı notu diye not al", "süt almayı listeme ekle", "notuma süt ekle", "alışveriş notumu oku",
        "alışveriş notuma bak", "yarın sabah süt almayı hatırlat",
    ])
    func notAddition(command: String) {
        #expect(NoteRequest.addition(in: command) == nil)
    }

    @Test("listing notes", arguments: [
        ("notlarım neler", AssistantLanguage.turkish, true), ("son notlarım", .turkish, true),
        ("hangi notlarım var", .turkish, true), ("notlarımı listele", .turkish, true),
        ("son notumu oku", .turkish, false), ("notlarımı aç", .turkish, false), ("tarif notumu oku", .turkish, false),
        ("notlarımda süt var mı", .turkish, false),
        ("list my notes", .english, true), ("what notes do I have", .english, true),
        ("show my recent notes", .english, true), ("read my recipe note", .english, false),
        ("open my notes", .english, false), ("add milk to my notes", .english, false),
    ])
    func listing(command: String, language: AssistantLanguage, expected: Bool) {
        #expect(NoteRequest.asksForList(command, language: language) == expected)
    }
}
