import Testing
@testable import AsistanCore

@Suite("TurkishText")
struct TurkishTextTests {
    @Test("lowercases with Turkish dotted/dotless I rules")
    func turkishLowercase() {
        #expect(TurkishText.lowercased("IŞIK İZMİR") == "ışık izmir")
    }

    @Test("normalizes punctuation and whitespace")
    func normalizesPunctuation() {
        #expect(TurkishText.normalized("  Hey,   Asistan!  Saat kaç? ") == "hey asistan saat kaç")
    }

    @Test("keeps apostrophe-separated suffixes as part of the word")
    func apostropheSuffix() {
        #expect(TurkishText.normalized("Safari'yi aç") == "safariyi aç")
        #expect(TurkishText.normalized("Safari’yi aç") == "safariyi aç")
    }

    @Test("folds Turkish diacritics for fuzzy matching")
    func foldsDiacritics() {
        #expect(TurkishText.folded("Çığ Şövalyesi Üzgün") == "cig sovalyesi uzgun")
    }

    @Test("returns empty string for punctuation-only input")
    func emptyInput() {
        #expect(TurkishText.normalized("...!?") == "")
    }
}
