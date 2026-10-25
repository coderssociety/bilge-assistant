import Testing
@testable import AsistanCore

@Suite("CurrencyRequest")
struct CurrencyRequestTests {
    typealias Parsed = CurrencyRequest.Parsed

    @Test("reads the currencies and amount said", arguments: [
        ("100 Euro kaç para", Parsed(from: "EUR", to: "TRY", amount: 100, asksAboutGold: false)),
        ("Ben 100 €'yu sormuştum", Parsed(from: "EUR", to: nil, amount: 100, asksAboutGold: false)),
        ("dolar kaç lira", Parsed(from: "USD", to: "TRY", amount: nil, asksAboutGold: false)),
        ("50 dolar kaç lira eder", Parsed(from: "USD", to: "TRY", amount: 50, asksAboutGold: false)),
        ("1000 lira kaç dolar", Parsed(from: "TRY", to: "USD", amount: 1000, asksAboutGold: false)),
        ("200 avro kaç TL", Parsed(from: "EUR", to: "TRY", amount: 200, asksAboutGold: false)),
        ("£20 kaç para", Parsed(from: "GBP", to: "TRY", amount: 20, asksAboutGold: false)),
        ("$250 kaç euro", Parsed(from: "USD", to: "EUR", amount: 250, asksAboutGold: false)),
        ("sterlin ne kadar", Parsed(from: "GBP", to: nil, amount: nil, asksAboutGold: false)),
        ("2,5 Kanada doları kaç İsviçre frangı", Parsed(from: "CAD", to: "CHF", amount: 2.5, asksAboutGold: false)),
        ("1.500 dolar kaç lira", Parsed(from: "USD", to: "TRY", amount: 1500, asksAboutGold: false)),
        ("convert 50 dollars to euros", Parsed(from: "USD", to: "EUR", amount: 50, asksAboutGold: false)),
    ])
    func parses(text: String, expected: Parsed) {
        #expect(CurrencyRequest.parse(text) == expected)
    }

    @Test("notices gold, which is not a currency", arguments: ["gram altın ne kadar", "çeyrek altın kaç lira", "price of gold"])
    func gold(text: String) {
        #expect(CurrencyRequest.parse(text).asksAboutGold)
    }
}
