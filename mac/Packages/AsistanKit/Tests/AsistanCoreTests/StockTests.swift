import Foundation
import Testing
@testable import AsistanCore

@Suite("Stocks")
struct StockTests {
    /// Trimmed from Yahoo's live chart answer for ASELS.IS (range=1d, interval=1d).
    private let aselsan = """
    {"chart":{"result":[{"meta":{"currency":"TRY","symbol":"ASELS.IS","exchangeName":"IST","regularMarketTime":1792768194,\
    "regularMarketPrice":338.0,"regularMarketChangePercent":-0.074,"chartPreviousClose":338.25,"longName":"ASELSAN"},\
    "timestamp":[1792768194],"indicators":{"quote":[{}]}}],"error":null}}
    """
    private let index = """
    {"chart":{"result":[{"meta":{"currency":"TRY","symbol":"XU100.IS","regularMarketTime":1792768211,\
    "regularMarketPrice":11116.99,"chartPreviousClose":11220.4,"previousClose":11220.4}}],"error":null}}
    """
    private let missing = #"{"chart":{"result":null,"error":{"code":"Not Found","description":"No data found"}}}"#

    private var calendar: Calendar {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "Europe/Istanbul")!
        return calendar
    }

    @Test("company names and tickers", arguments: [
        ("THY hissesi ne kadar", "THYAO.IS"), ("Türk Hava Yolları bugün", "THYAO.IS"), ("Aselsan'ın hissesi", "ASELS.IS"),
        ("BIST 100 kaç", "XU100.IS"), ("bist otuz", "XU030.IS"), ("Garanti hisseleri", "GARAN.IS"),
        ("how is Turkish Airlines stock doing", "THYAO.IS"),
    ])
    func symbols(text: String, ticker: String) {
        #expect(StockRequest.symbols(in: text).first?.ticker == ticker)
    }

    @Test("the market as a whole is the BIST 100")
    func market() {
        #expect(StockRequest.symbols(in: "borsa nasıl") == [StockSymbols.bist100])
        #expect(StockRequest.symbols(in: "THY ve Aselsan ne kadar").map(\.ticker) == ["THYAO.IS", "ASELS.IS"])
    }

    @Test("a quote, with the change given or worked out")
    func parsesQuotes() throws {
        let quote = try YahooChart.quote(Data(aselsan.utf8))
        #expect(quote.price == 338 && quote.changePercent == -0.074 && quote.currency == "TRY")
        let computed = try #require(try YahooChart.quote(Data(index.utf8)).changePercent)
        #expect(abs(computed - -0.9216) < 0.001)
        #expect(throws: StockDataError.notFound) { try YahooChart.quote(Data(missing.utf8)) }
        #expect(throws: StockDataError.unreadable) { try YahooChart.quote(Data("<html>".utf8)) }
    }

    @Test("prices as spoken, open and closed")
    func spoken() throws {
        let quote = try YahooChart.quote(Data(aselsan.utf8))
        let marketTime = try #require(quote.marketTime)
        let aselsan = try #require(StockRequest.symbols(in: "Aselsan").first)
        let live = StockReport(now: marketTime.addingTimeInterval(600), calendar: calendar, language: .turkish)
        #expect(live.text(aselsan, quote) == "Aselsan hissesi şu an 338 lira, günlük %0,07 düşüşte.")
        let sunday = StockReport(now: marketTime.addingTimeInterval(2 * 86_400), calendar: calendar, language: .turkish)
        #expect(sunday.text(aselsan, quote) == "Aselsan hissesi Cuma günü 338 liradan, %0,07 düşüşle kapandı.")
        let index = try YahooChart.quote(Data(self.index.utf8))
        #expect(sunday.text(StockSymbols.bist100, index) == "BIST 100 endeksi Cuma günü 11.116,99 puanla, %0,92 düşüşle kapandı.")
        let english = StockReport(now: marketTime.addingTimeInterval(2 * 86_400), calendar: calendar, language: .english)
        #expect(english.text(StockSymbols.bist100, index) == "The BIST 100 closed on Friday at 11,116.99 points, down 0.92%.")
        let thy = try #require(StockRequest.symbols(in: "THY").first)
        #expect(english.text(thy, quote).hasPrefix("Turkish Airlines closed on Friday at 338 lira"))
    }

    @Test("stock questions and others", arguments: [
        ("borsa nasıl", true), ("BIST 100 kaç", true), ("THY hissesi ne kadar", true), ("Aselsan bugün", true),
        ("Aselsan", true), ("THY bileti ne kadar", false), ("borsa nedir", false), ("THY almalı mıyım", false),
        ("borsa haberleri", false), ("Aselsan'da çalışıyorum", false),
    ])
    func requests(text: String, expected: Bool) {
        #expect(StockRequest.isRequest(text) == expected)
    }
}
