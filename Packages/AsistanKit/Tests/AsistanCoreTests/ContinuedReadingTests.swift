import Foundation
import Testing
@testable import AsistanCore

@Suite("Continued reading")
struct ContinuedReadingTests {
    private let start = Date(timeIntervalSince1970: 1_000_000)

    @Test("a short text is a single part")
    func shortText() {
        #expect(ContinuedReading.parts(of: "Kısa bir not.", layout: .text(maxCharacters: 100)) == ["Kısa bir not."])
    }

    @Test("prose is cut at a paragraph end, else a sentence end, else a space")
    func breaks() {
        let paragraphs = "Birinci paragraf burada.\nİkinci paragraf daha uzun bir cümle."
        #expect(ContinuedReading.parts(of: paragraphs, layout: .text(maxCharacters: 40))
            == ["Birinci paragraf burada.", "İkinci paragraf daha uzun bir cümle."])
        let sentences = "Bu ilk cümle biraz daha uzun. İkinci cümle burada."
        #expect(ContinuedReading.parts(of: sentences, layout: .text(maxCharacters: 40))
            == ["Bu ilk cümle biraz daha uzun.", "İkinci cümle burada."])
        let words = "kelime kelime kelime kelime"
        #expect(ContinuedReading.parts(of: words, layout: .text(maxCharacters: 15)) == ["kelime kelime", "kelime kelime"])
    }

    @Test("a decimal point is not a sentence end")
    func decimal() {
        let parts = ContinuedReading.parts(of: "Oran 3.5 oldu bugün", layout: .text(maxCharacters: 12))
        #expect(parts.first == "Oran 3.5")
    }

    @Test("every character is kept across parts")
    func nothingLost() {
        let text = (1...300).map { "Cümle \($0) burada bitiyor." }.joined(separator: " ")
        let parts = ContinuedReading.parts(of: text, layout: .text(maxCharacters: 500))
        #expect(parts.count > 1)
        #expect(parts.allSatisfy { $0.count <= 500 })
        #expect(parts.joined(separator: " ") == text)
    }

    @Test("lists are cut between items")
    func list() {
        let text = "5 kestirmen var: A, B, C, D, E"
        #expect(ContinuedReading.parts(of: text, layout: .list(separator: ", ", perPart: 2))
            == ["5 kestirmen var: A, B", "C, D", "E"])
    }

    @Test("goes on part by part and says when nothing is left")
    func goesOn() throws {
        var reading = try #require(ContinuedReading("A, B, C", layout: .list(separator: ", ", perPart: 1),
                                                    answersWithLanguageModel: false, at: start))
        #expect(reading.firstPart == "A")
        #expect(reading.hasMore)
        #expect(reading.next(at: start) == "B")
        #expect(reading.lastPart == "B")
        #expect(reading.next(at: start) == "C")
        #expect(!reading.hasMore)
        #expect(reading.next(at: start) == nil)
        #expect(reading.lastPart == "C")
    }

    @Test("without a layout the text is read whole; an empty text is no reading")
    func whole() throws {
        let reading = try #require(ContinuedReading("Ekran metni", layout: nil, answersWithLanguageModel: true, at: start))
        #expect(reading.parts == ["Ekran metni"])
        #expect(ContinuedReading("  ", layout: .text(maxCharacters: 10), answersWithLanguageModel: true, at: start) == nil)
    }

    @Test("expires a while after the last part was read")
    func expiry() throws {
        var reading = try #require(ContinuedReading("a b c d", layout: .text(maxCharacters: 3),
                                                    answersWithLanguageModel: false, at: start))
        #expect(reading.isCurrent(at: start.addingTimeInterval(60)))
        #expect(!reading.isCurrent(at: start.addingTimeInterval(ContinuedReading.lifetime)))
        _ = reading.next(at: start.addingTimeInterval(600))
        #expect(reading.isCurrent(at: start.addingTimeInterval(ContinuedReading.lifetime)))
    }

    @Test("continuation requests", arguments: [
        "devamını oku", "Devam et", "devam", "sonrası", "sonrasını okur musun", "gerisini oku", "kalanını oku",
        "okumaya devam et", "kaldığın yerden devam et", "diğerlerini söyle", "başka var mı", "sonraki kısmı oku",
    ])
    func continuation(command: String) {
        #expect(ReadingRequest.isContinuation(command))
    }

    @Test("other commands are not continuations", arguments: [
        "müziğe devam et", "sonraki şarkı", "başka bir kaynak", "Ahmet'e sonra ara diye yaz", "saat kaç", "oku",
    ])
    func notContinuation(command: String) {
        #expect(!ReadingRequest.isContinuation(command))
    }

    @Test("English continuation requests", arguments: [
        "read more", "continue", "go on", "keep reading", "what's next", "read the rest", "next part", "is there more",
    ])
    func englishContinuation(command: String) {
        #expect(ReadingRequest.isContinuation(command, language: .english))
    }

    @Test("other English commands are not continuations", arguments: [
        "next song", "turn on the lights", "tell me more about the second one", "read my notes",
    ])
    func englishNotContinuation(command: String) {
        #expect(!ReadingRequest.isContinuation(command, language: .english))
    }
}
