import Foundation
import Testing
@testable import AsistanCore

@Suite("Encyclopedia")
struct EncyclopediaTests {
    @Test("the subject of a clear encyclopedic question", arguments: [
        ("Mustafa Kemal Atatürk kimdir", "Mustafa Kemal Atatürk"),
        ("fotosentez nedir?", "fotosentez"),
        ("Everest hakkında bilgi ver", "Everest"),
        ("bana kara delikler hakkında bilgi verir misin", "kara delikler"),
        ("entropi ne demek", "entropi"),
        ("Nirvana'nın anlamı nedir", "Nirvana"),
        ("Barış Manço kim", "Barış Manço"),
    ])
    func turkish(text: String, subject: String) {
        #expect(EncyclopediaQuestion.subject(in: text, language: .turkish) == subject)
    }

    @Test("small talk, Mac questions and relations stay with the conversation", arguments: [
        "nasılsın", "saat kaç", "senin adın nedir", "bu ne demek", "ekranda yazan nedir", "pil durumu nedir",
        "Osmanlı Devleti'nin kurucusu kimdir", "Pi sayısının ilk üç basamağı nedir", "Ay'a ilk kim gitti",
        "dünyanın en yüksek dağı nedir", "sorun nedir", "Nobel Edebiyat Ödülü alan Türk yazar kim",
    ])
    func notTurkish(text: String) {
        #expect(EncyclopediaQuestion.subject(in: text, language: .turkish) == nil)
    }

    @Test("English questions")
    func english() {
        #expect(EncyclopediaQuestion.subject(in: "who was Ada Lovelace?", language: .english) == "Ada Lovelace")
        #expect(EncyclopediaQuestion.subject(in: "what is photosynthesis", language: .english) == "photosynthesis")
        #expect(EncyclopediaQuestion.subject(in: "tell me about the Eiffel Tower", language: .english) == "the Eiffel Tower")
        #expect(EncyclopediaQuestion.subject(in: "what does entropy mean", language: .english) == "entropy")
        for text in ["what time is it", "what is the weather like", "who are you", "what's up", "what is the capital of France",
                     "what is 5 plus 3", "what is Newton's law"] {
            #expect(EncyclopediaQuestion.subject(in: text, language: .english) == nil, "\(text)")
        }
    }

    @Test("summary, disambiguation and search results")
    func parser() throws {
        let page = try #require(WikipediaParser.summary(WikipediaFixtures.wikipediaSummary))
        #expect(page.title == "Fotosentez")
        #expect(!page.isDisambiguation)
        #expect(WikipediaParser.summary(WikipediaFixtures.wikipediaDisambiguation)?.isDisambiguation == true)
        #expect(WikipediaParser.summary(Data(#"{"status":404,"type":"Internal error"}"#.utf8)) == nil)
        #expect(WikipediaParser.openSearchTitles(WikipediaFixtures.wikipediaOpenSearch).first == "Atatürk")
        #expect(WikipediaParser.openSearchTitles(Data("[]".utf8)).isEmpty)
    }

    @Test("title paths and the material handed to the model")
    func material() throws {
        #expect(WikipediaParser.titlePath("Mustafa Kemal Atatürk") == "Mustafa_Kemal_Atat%C3%BCrk")
        #expect(WikipediaParser.titlePath("AC/DC") == "AC%2FDC")
        let page = try #require(WikipediaParser.summary(WikipediaFixtures.wikipediaSummary))
        let short = WikipediaParser.material(page, maxCharacters: 140, language: .turkish)
        #expect(short.hasPrefix("Vikipedi — Fotosentez:\n"))
        #expect(short.hasSuffix("bir işlemdir."))
    }
}
