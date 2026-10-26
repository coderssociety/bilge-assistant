import Foundation

/// Recognises questions about Borsa İstanbul prices ("borsa nasıl", "THY hissesi ne kadar", "Aselsan bugün").
/// Only figures are given; whether to buy or sell is not this tool's question.
public enum StockRequest {
    public static let maximumSymbols = 3
    private static let marketStems = ["borsa", "bist", "hisse", "endeks", "xu100"]
    private static let priceStems = [
        "ne kadar", "kac", "fiyat", "deger", "durum", "nasil", "yuksel", "dus", "art", "kazandir", "kaybet", "bugun",
        "kapanis", "kapatti", "kapandi", "ne oldu", "puan",
    ]
    private static let otherStems = [
        "haber", "bilet", "ucus", "ucak", "sefer", "rezervasyon", "bagaj", "hatirlat", "nedir", "ne demek", "almali",
        "satmali", "alayim", "satayim", "alinir", "tavsiye", "oner", "yatirim yap", "not al", "mesaj",
    ]
    private static let englishMarketStems = ["stock", "shares", "share price", "bist", "borsa", "xu100"]
    private static let englishPriceStems = [
        "price", "how much", "trading", "today", "doing", "up", "down", "worth", "close", "closed",
    ]
    private static let englishOtherStems = [
        "news", "ticket", "flight", "booking", "remind", "what is", "should i", "advice", "recommend", "buy", "sell",
        "note", "text",
    ]
    /// A company named with no other word ("Aselsan?") still asks for its price.
    private static let bareNameWords = 1

    public static func isRequest(_ text: String, language: AssistantLanguage = .turkish) -> Bool {
        let folded = " " + TurkishText.folded(text) + " "
        let has = { (stems: [String]) in stems.contains { folded.contains(" " + $0) } }
        let english = language == .english
        guard !has(english ? englishOtherStems : otherStems) else { return false }
        if has(english ? englishMarketStems : marketStems) { return true }
        guard !StockSymbols.named(in: text).isEmpty else { return false }
        let wordCount = folded.split(separator: " ").count
        return has(english ? englishPriceStems : priceStems) || wordCount <= bareNameWords
    }

    /// The symbols asked about; the BIST 100 when the market as a whole is.
    public static func symbols(in text: String) -> [StockSymbol] {
        let named = StockSymbols.named(in: text)
        return named.isEmpty ? [StockSymbols.bist100] : Array(named.prefix(maximumSymbols))
    }
}

public struct StockQuote: Sendable, Equatable {
    public let symbol: String
    public let price: Double
    public let changePercent: Double?
    public let currency: String?
    public let marketTime: Date?

    public init(symbol: String, price: Double, changePercent: Double?, currency: String?, marketTime: Date?) {
        self.symbol = symbol
        self.price = price
        self.changePercent = changePercent
        self.currency = currency
        self.marketTime = marketTime
    }
}

public enum StockDataError: Error, Equatable {
    case notFound, unreadable
}

/// Yahoo Finance's chart service (query1/query2.finance.yahoo.com/v8/finance/chart/<symbol>): only the
/// summary in `meta` is used.
public enum YahooChart {
    private struct Response: Decodable {
        struct Chart: Decodable { let result: [Result]? }
        struct Result: Decodable { let meta: Meta }
        struct Meta: Decodable {
            let symbol: String?
            let currency: String?
            let regularMarketPrice: Double?
            let regularMarketChangePercent: Double?
            let chartPreviousClose: Double?
            let previousClose: Double?
            let regularMarketTime: Double?
        }
        let chart: Chart
    }

    public static func quote(_ data: Data) throws -> StockQuote {
        guard let response = try? JSONDecoder().decode(Response.self, from: data) else { throw StockDataError.unreadable }
        guard let meta = response.chart.result?.first?.meta, let price = meta.regularMarketPrice else {
            throw StockDataError.notFound
        }
        let previous = meta.previousClose ?? meta.chartPreviousClose
        let change = meta.regularMarketChangePercent ?? previous.flatMap { $0 > 0 ? (price - $0) / $0 * 100 : nil }
        return StockQuote(symbol: meta.symbol ?? "", price: price, changePercent: change, currency: meta.currency,
                          marketTime: meta.regularMarketTime.map { Date(timeIntervalSince1970: $0) })
    }
}

/// A price and the day's change as one spoken sentence.
public struct StockReport: Sendable {
    /// Borsa İstanbul's prices come about 15 minutes late; a price this recent counts as the market being open.
    static let liveWindow: TimeInterval = 30 * 60

    public let now: Date
    public let calendar: Calendar
    public let language: AssistantLanguage

    public init(now: Date, calendar: Calendar = .current, language: AssistantLanguage) {
        self.now = now
        self.calendar = calendar
        self.language = language
    }

    public func text(_ symbol: StockSymbol, _ quote: StockQuote) -> String {
        let price = number(quote.price)
        let unit = unit(symbol, quote)
        let percent = quote.changePercent.map { abs($0) }.map(number) ?? ""
        let direction = (quote.changePercent ?? 0) * 100
        let isLive = quote.marketTime.map { now.timeIntervalSince($0) < Self.liveWindow } ?? true
        let day = quote.marketTime.map(dayPhrase) ?? ""
        if language == .english {
            let name = symbol.isIndex ? "The \(symbol.spokenName(language))" : symbol.spokenName(language)
            let change = direction.rounded() == 0 || quote.changePercent == nil ? "unchanged" : "\(direction > 0 ? "up" : "down") \(percent)%"
            return isLive ? "\(name) is at \(price) \(unit), \(change) today." : "\(name) closed \(day) at \(price) \(unit), \(change)."
        }
        let name = symbol.isIndex ? "\(symbol.name) endeksi" : "\(symbol.name) hissesi"
        let flat = direction.rounded() == 0 || quote.changePercent == nil
        if isLive {
            let change = flat ? "günlük değişim yok" : "günlük %\(percent) \(direction > 0 ? "yükselişte" : "düşüşte")"
            return "\(name) şu an \(price) \(unit), \(change)."
        }
        let at = symbol.isIndex ? "\(price) puanla" : "\(price) \(unit == "lira" ? "liradan" : unit)"
        let change = flat ? "değişmeden" : "%\(percent) \(direction > 0 ? "yükselişle" : "düşüşle")"
        return "\(name) \(day) \(at), \(change) kapandı."
    }

    private func unit(_ symbol: StockSymbol, _ quote: StockQuote) -> String {
        if symbol.isIndex { return language == .english ? "points" : "puan" }
        guard let currency = quote.currency, currency != "TRY" else { return "lira" }
        return currency
    }

    private func number(_ value: Double) -> String {
        value.formatted(.number.precision(.fractionLength(0...2)).locale(language.locale))
    }

    private func dayPhrase(_ date: Date) -> String {
        let days = calendar.dateComponents([.day], from: calendar.startOfDay(for: date), to: calendar.startOfDay(for: now)).day ?? 0
        let format = Date.FormatStyle(date: .omitted, time: .omitted, locale: language.locale, calendar: calendar,
                                      timeZone: calendar.timeZone)
        switch (language, days) {
        case (.english, 0): return "today"
        case (.english, 1): return "yesterday"
        case (.english, 2...6): return "on " + date.formatted(format.weekday(.wide))
        case (.english, _): return "on " + date.formatted(format.month(.wide).day())
        case (.turkish, 0): return "bugün"
        case (.turkish, 1): return "dün"
        case (.turkish, 2...6): return date.formatted(format.weekday(.wide)) + " günü"
        case (.turkish, _): return date.formatted(format.day().month(.wide)) + " tarihinde"
        }
    }
}
