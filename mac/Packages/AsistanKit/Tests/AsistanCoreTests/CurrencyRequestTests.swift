import Testing
@testable import AsistanCore

@Suite("CurrencyRequest")
struct CurrencyRequestTests {
    typealias Parsed = CurrencyRequest.Parsed

    @Test("reads the currencies and amount said", arguments: [
        ("100 Euro kaç para", Parsed(from: "EUR", to: "TRY", amount: 100)),
        ("Ben 100 €'yu sormuştum", Parsed(from: "EUR", to: nil, amount: 100)),
        ("dolar kaç lira", Parsed(from: "USD", to: "TRY", amount: nil)),
        ("50 dolar kaç lira eder", Parsed(from: "USD", to: "TRY", amount: 50)),
        ("1000 lira kaç dolar", Parsed(from: "TRY", to: "USD", amount: 1000)),
        ("200 avro kaç TL", Parsed(from: "EUR", to: "TRY", amount: 200)),
        ("£20 kaç para", Parsed(from: "GBP", to: "TRY", amount: 20)),
        ("$250 kaç euro", Parsed(from: "USD", to: "EUR", amount: 250)),
        ("sterlin ne kadar", Parsed(from: "GBP", to: nil, amount: nil)),
        ("2,5 Kanada doları kaç İsviçre frangı", Parsed(from: "CAD", to: "CHF", amount: 2.5)),
        ("1.500 dolar kaç lira", Parsed(from: "USD", to: "TRY", amount: 1500)),
        ("convert 50 dollars to euros", Parsed(from: "USD", to: "EUR", amount: 50)),
        ("dolar ve euro kaç lira", Parsed(from: "USD", to: "TRY", amount: nil, alsoFrom: "EUR")),
        ("dolar ve euro ne kadar", Parsed(from: "USD", to: nil, amount: nil, alsoFrom: "EUR")),
        ("dolar euro kaç TL", Parsed(from: "USD", to: "TRY", amount: nil, alsoFrom: "EUR")),
        ("100 doları liraya çevir", Parsed(from: "USD", to: "TRY", amount: 100)),
        ("500 lirayı dolara çevir", Parsed(from: "TRY", to: "USD", amount: 500)),
        ("euro dolar paritesi", Parsed(from: "EUR", to: "USD", amount: nil)),
        ("1.000.000 lira kaç dolar", Parsed(from: "TRY", to: "USD", amount: 1_000_000)),
        ("2.500,50 euro kaç TL", Parsed(from: "EUR", to: "TRY", amount: 2500.5)),
        ("2.5 dollars in euros", Parsed(from: "USD", to: "EUR", amount: 2.5)),
        ("1.2.3 dolar kaç lira", Parsed(from: "USD", to: "TRY", amount: nil)),
    ])
    func parses(text: String, expected: Parsed) {
        #expect(CurrencyRequest.parse(text) == expected)
    }
}
