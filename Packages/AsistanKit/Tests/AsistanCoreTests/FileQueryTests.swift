import Testing
@testable import AsistanCore

@Suite("File queries")
struct FileQueryTests {
    @Test("kind, time and name are found in any order", arguments: [
        ("dün indirdiğim excel dosyası", FileQuery(kinds: [.spreadsheet], period: .yesterday)),
        ("excel dün", FileQuery(kinds: [.spreadsheet], period: .yesterday)),
        ("geçen haftaki bütçe sunumu", FileQuery(nameWords: ["bütçe"], kinds: [.presentation], period: .lastWeek)),
        ("bütçe sunum geçen hafta", FileQuery(nameWords: ["bütçe"], kinds: [.presentation], period: .lastWeek)),
        ("son indirdiğim PDF'i", FileQuery(kinds: [.pdf])),
        ("Ahmet'in raporu word", FileQuery(nameWords: ["Ahmet", "raporu"], kinds: [.wordProcessing])),
        ("bugün kaydettiğim resimler", FileQuery(kinds: [.image], period: .today)),
        ("rapor.pdf", FileQuery(nameWords: ["rapor"], kinds: [.pdf])),
        ("vergi", FileQuery(nameWords: ["vergi"])),
        ("Invoice", FileQuery(nameWords: ["Invoice"])),
        ("the budget presentation from last week", FileQuery(nameWords: ["budget"], kinds: [.presentation], period: .lastWeek)),
    ])
    func parse(text: String, expected: FileQuery) {
        #expect(FileQuery.parse(text) == expected)
    }

    @Test("builds a Spotlight query")
    func spotlight() {
        let query = FileQuery(nameWords: ["bütçe"], kinds: [.pdf], period: .yesterday)
        #expect(query.spotlightQuery == "kMDItemFSName == \"*bütçe*\"cd && (kMDItemFSName == \"*.pdf\"c)"
            + " && kMDItemFSContentChangeDate >= $time.yesterday && kMDItemFSContentChangeDate < $time.today")
        #expect(FileQuery(kinds: [.presentation]).spotlightQuery
            == "(kMDItemFSName == \"*.key\"c || kMDItemFSName == \"*.odp\"c || kMDItemFSName == \"*.ppt\"c || kMDItemFSName == \"*.pptx\"c)")
        #expect(FileQuery(period: .lastWeek).spotlightQuery
            == "kMDItemFSContentChangeDate >= $time.this_week(-1) && kMDItemFSContentChangeDate < $time.this_week")
    }

    @Test("spoken quotes and wildcards cannot change the query")
    func quotes() {
        #expect(FileQuery.parse("rapor\" || kMDItemFSName == \"*").spotlightQuery
            == "kMDItemFSName == \"*rapor*\"cd && kMDItemFSName == \"*kMDItemFSName*\"cd")
    }

    @Test("an extracted query gets the kind and time said in the command, and round-trips as text")
    func filters() {
        let extracted = FileQuery.parse("bütçe")
        let refined = extracted.addingFilters(of: FileQuery.parse("dün indirdiğim bütçe excelini bul"))
        #expect(refined == FileQuery(nameWords: ["bütçe"], kinds: [.spreadsheet], period: .yesterday))
        #expect(FileQuery.parse(refined.text) == refined)
        #expect(FileQuery.parse("son dosyayı aç").isEmpty)
    }

    @Test("kinds give their extensions")
    func extensions() {
        #expect(FileQuery(kinds: [.pdf, .spreadsheet]).extensions == ["pdf", "xlsx", "xls", "numbers", "csv", "ods"])
        #expect(FileQuery().extensions.isEmpty)
    }
}
