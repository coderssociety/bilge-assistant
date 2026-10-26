import Foundation
import Testing
@testable import AsistanCore

@Suite("GoldPrice")
struct GoldPriceTests {
    @Test("reads the kinds asked for", arguments: [
        ("gram altın ne kadar", [GoldKind.gram]),
        ("çeyrek altın kaç lira", [.quarter]),
        ("cumhuriyet altını", [.republic]),
        ("ons ne kadar", [.ounce]),
        ("altın fiyatları", GoldKind.usual),
        ("altın düştü mü", GoldKind.usual),
        ("tam altın ile yarım altın kaç para", [.full, .half]),
        ("22 ayar bilezik gramı ne kadar", [.carat22]),
    ])
    func turkishKinds(text: String, expected: [GoldKind]) {
        #expect(GoldQuestion.kinds(in: text, language: .turkish) == expected)
    }

    @Test("gold words that are not about prices", arguments: [
        "altın oran nedir", "Altın Portakal ne zaman", "dolar kaç lira", "100 gram un kaç kalori", "tam olarak saat kaç",
        "gram altın fiyatını Ahmet'e mesaj at",
    ])
    func notGold(text: String) {
        #expect(GoldQuestion.kinds(in: text, language: .turkish) == nil)
    }

    @Test("English requests")
    func english() {
        #expect(GoldQuestion.kinds(in: "how much is gold", language: .english) == GoldKind.usual)
        #expect(GoldQuestion.kinds(in: "price of a quarter gold coin", language: .english) == [.quarter])
        #expect(GoldQuestion.kinds(in: "gold price per ounce", language: .english) == [.ounce])
        #expect(GoldQuestion.kinds(in: "what is the golden ratio", language: .english) == nil)
    }

    @Test("reads Turkish-formatted and numeric prices")
    func numbers() {
        #expect(PriceNumber.parse("6.384,76") == 6384.76)
        #expect(PriceNumber.parse("$3.995,89") == 3995.89)
        #expect(PriceNumber.parse("10.285") == 10285)
        #expect(PriceNumber.parse("77.50") == 77.5)
        #expect(PriceNumber.parse(6383.95) == 6383.95)
        #expect(PriceNumber.parse("bozuk") == nil)
        #expect(PriceNumber.parse(nil) == nil)
    }

    @Test("finans.truncgil.com, both formats")
    func truncgil() {
        let quotes = GoldPriceParser.truncgil(GoldFixtures.truncgil)
        #expect(quotes[.gram] == GoldQuote(buying: 6383.95, selling: 6384.76))
        #expect(quotes[.ounce] == GoldQuote(buying: 3995.89, selling: 3996.40))
        #expect(quotes[.carat22] == GoldQuote(buying: 5883.67, selling: 5890.59))
        #expect(quotes[.half] == nil)
        let v4 = GoldPriceParser.truncgil(GoldFixtures.truncgilV4)
        #expect(v4[.gram] == GoldQuote(buying: 6383.95, selling: 6384.76))
        #expect(v4[.half] == nil)
        #expect(GoldPriceParser.truncgil(Data("<html>".utf8)).isEmpty)
    }

    @Test("Altınkaynak and gold-api.com fallbacks")
    func fallbacks() {
        let quotes = GoldPriceParser.altinkaynak(GoldFixtures.altinkaynak)
        #expect(quotes[.gram] == GoldQuote(buying: 6399, selling: 6510))
        #expect(quotes[.quarter] == GoldQuote(buying: 10331, selling: 10645))
        #expect(quotes[.republic] == GoldQuote(buying: 42246, selling: 43295))
        #expect(quotes.count == 3)
        #expect(GoldPriceParser.ounce(GoldFixtures.goldAPI)?.selling == 3996.899902)
        #expect(GoldPriceParser.ounce(Data(#"{"symbol":"XAG","price":31.2}"#.utf8)) == nil)
    }

    @Test("spoken answers")
    func report() {
        let quotes = GoldPriceParser.truncgil(GoldFixtures.truncgil)
        #expect(GoldReport.text(quotes, kinds: [.gram], language: .turkish) == "Gram altın alış 6.384, satış 6.385 lira.")
        #expect(GoldReport.text(quotes, kinds: GoldKind.usual, language: .turkish)
            == "Satış fiyatları: gram altın 6.385 lira, çeyrek altın 10.560 lira.")
        #expect(GoldReport.text(quotes, kinds: [.ounce], language: .english) == "Gold per ounce: buying 3,996, selling 3,996 dollars.")
        #expect(GoldReport.text(quotes, kinds: [.half], language: .turkish) == nil)
    }
}
