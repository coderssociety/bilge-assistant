import Testing
@testable import AsistanCore

@Suite("SentenceSplitter")
struct SentenceSplitterTests {
    @Test("splits on terminal punctuation")
    func basicSplit() {
        #expect(SentenceSplitter.split("Merhaba! Nasılsın? Bugün hava güzel.") ==
            ["Merhaba!", "Nasılsın?", "Bugün hava güzel."])
    }

    @Test("does not split inside decimals, times or common abbreviations")
    func protectedDots() {
        #expect(SentenceSplitter.split("Saat 14.30'da Dr. Ayşe ile görüşme var. Fiyat 3.5 lira.") ==
            ["Saat 14.30'da Dr. Ayşe ile görüşme var.", "Fiyat 3.5 lira."])
    }

    @Test("breaks overly long sentences at commas")
    func longSentence() {
        let long = "Bugün önce markete gideceğiz, sonra eczaneye uğrayıp ilaçları alacağız, ardından eve dönüp yemeği hazırlayacağız ve akşam da misafirleri ağırlayacağız."
        let parts = SentenceSplitter.split(long, maxLength: 80)
        #expect(parts.count > 1)
        #expect(parts.allSatisfy { $0.count <= 80 })
        #expect(parts.joined(separator: " ") == long)
    }

    @Test("ignores blank input")
    func blank() {
        #expect(SentenceSplitter.split("   \n ").isEmpty)
    }
}

@Suite("SentenceAccumulator")
struct SentenceAccumulatorTests {
    @Test("emits sentences as streamed fragments complete them")
    func streaming() {
        var accumulator = SentenceAccumulator()
        #expect(accumulator.append("Tamam, Safari") == [])
        #expect(accumulator.append("'yi açıyorum. Başka bir") == ["Tamam, Safari'yi açıyorum."])
        #expect(accumulator.append(" şey var mı?") == [])
        #expect(accumulator.finish() == ["Başka bir şey var mı?"])
    }

    @Test("waits for the next character before treating a dot as a sentence end")
    func trailingDotIsAmbiguous() {
        var accumulator = SentenceAccumulator()
        #expect(accumulator.append("Saat 14.") == [])
        #expect(accumulator.append("30 oldu. ") == ["Saat 14.30 oldu."])
        #expect(accumulator.finish() == [])
    }
}
