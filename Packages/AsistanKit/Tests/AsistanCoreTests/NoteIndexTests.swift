import Testing
@testable import AsistanCore

@Suite("Note index")
struct NoteIndexTests {
    private let separator = NoteIndex.blockSeparator

    private var output: String {
        "id1\nid2\nid3\nid4\n\(separator)\nEski alışveriş listesi\nToplantı\n\nAlışveriş\n\(separator)\n900\n60\n30\n7200"
    }

    @Test("ids, names and ages are read line for line")
    func parses() {
        let entries = NoteIndex.parse(output)
        #expect(entries.count == 4)
        #expect(entries[1] == NoteIndex.Entry(id: "id2", name: "Toplantı", secondsSinceChange: 60))
    }

    @Test("blocks that do not line up give nothing rather than wrong pairs")
    func misaligned() {
        #expect(NoteIndex.parse("id1\nid2\n\(separator)\nTek\n\(separator)\n5\n6").isEmpty)
        #expect(NoteIndex.parse("").isEmpty)
        #expect(NoteIndex.parse("\(separator)\n\(separator)\n").isEmpty)
    }

    @Test("recent notes come first and untitled ones are left out")
    func recent() {
        let names = NoteIndex.recent(NoteIndex.parse(output), limit: 2).map(\.name)
        #expect(names == ["Toplantı", "Eski alışveriş listesi"])
    }

    @Test("a spoken name finds the note it means", arguments: [
        ("alışveriş", "id4"), ("toplantı", "id2"), ("eski alışveriş listesi", "id1"),
    ])
    func finds(spoken: String, id: String) {
        #expect(NoteIndex.find(spoken, in: NoteIndex.parse(output))?.id == id)
    }

    @Test("an unknown name finds nothing")
    func unknown() {
        #expect(NoteIndex.find("tarif", in: NoteIndex.parse(output)) == nil)
    }
}
