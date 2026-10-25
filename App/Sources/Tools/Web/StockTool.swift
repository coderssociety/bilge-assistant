import AsistanCore
import Foundation
import FoundationModels

/// Yahoo Finance's chart service, on its second host when the first fails.
enum StockFeed {
    private static let hosts = ["query1.finance.yahoo.com", "query2.finance.yahoo.com"]
    private static let quotes = TimedCache<StockQuote>()
    private static let freshness: TimeInterval = 60

    static func quote(_ ticker: String) async throws -> TimedCache<StockQuote>.Entry {
        try await quotes.value(for: ticker, maxAge: freshness) {
            do {
                return try await fetch(ticker, host: hosts[0])
            } catch StockDataError.notFound {
                throw StockDataError.notFound
            } catch is CancellationError {
                throw CancellationError()
            } catch {
                Log.tools.error("\(hosts[0], privacy: .public) failed for \(ticker, privacy: .public): \(error.localizedDescription, privacy: .public)")
                return try await fetch(ticker, host: hosts[1])
            }
        }
    }

    private static func fetch(_ ticker: String, host: String) async throws -> StockQuote {
        var url = URLComponents()
        url.scheme = "https"
        url.host = host
        url.path = "/v8/finance/chart/\(ticker)"
        url.queryItems = [.init(name: "range", value: "1d"), .init(name: "interval", value: "1d")]
        do {
            return try YahooChart.quote(try await WebFetch.data(from: url.url!))
        } catch WebFetchError.badStatus(404) {
            throw StockDataError.notFound
        }
    }
}

/// "Borsa nasıl", "BIST 100 kaç", "THY hissesi ne kadar". Only prices and the day's change are said, never
/// advice. Routed by rule (`RouteGuard.infoTopic`).
struct StockTool: RuleRoutedTool {
    let name = "stocks"
    let description = "Borsa İstanbul endekslerinin ve hisselerin fiyatını ve günlük değişimini söyler (Yahoo Finance)."

    @Generable
    struct Arguments {
        @Guide(description: "Kullanıcının isteği, olduğu gibi")
        var request: String
    }

    @MainActor
    func claims(_ command: String) -> Bool {
        RouteGuard.infoTopic(command, language: AppLanguage.current) == name
    }

    func arguments(fromCommand command: String) -> Arguments? {
        Arguments(request: command)
    }

    func call(arguments: Arguments) async throws -> String {
        let language = AppLanguage.current
        let request = language == .turkish ? TurkishNumberParser.digitize(arguments.request) : arguments.request
        let symbols = StockRequest.symbols(in: request)
        let report = StockReport(now: .now, language: language)
        let answers = await withTaskGroup(of: (Int, Result<TimedCache<StockQuote>.Entry, any Error>).self) { group in
            for (index, symbol) in symbols.enumerated() {
                group.addTask {
                    do { return (index, .success(try await StockFeed.quote(symbol.ticker))) } catch { return (index, .failure(error)) }
                }
            }
            var results: [Int: Result<TimedCache<StockQuote>.Entry, any Error>] = [:]
            for await (index, result) in group { results[index] = result }
            return symbols.indices.compactMap { results[$0] }
        }
        guard answers.contains(where: { if case .success = $0 { true } else { false } }) else {
            let reason = answers.first.map { result -> String in
                guard case let .failure(error) = result else { return "" }
                return Self.describe(error)
            } ?? ""
            return ToolReply.failure(String(localized: "Borsa verisi alınamadı. \(reason)"))
        }
        let sentences = zip(symbols, answers).map { symbol, result -> String in
            switch result {
            case let .success(entry): return entry.stalenessNote + report.text(symbol, entry.value)
            case let .failure(error):
                Log.tools.error("Quote for \(symbol.ticker, privacy: .public) failed: \(error.localizedDescription, privacy: .public)")
                return String(localized: "\(symbol.spokenName(AppLanguage.current)) için fiyat alınamadı.")
            }
        }
        return sentences.joined(separator: " ")
    }

    private static func describe(_ error: any Error) -> String {
        switch error {
        case StockDataError.notFound: String(localized: "Bu sembol için veri yok.")
        case StockDataError.unreadable: WebFetchError.unreadable.localizedDescription
        default: error.localizedDescription
        }
    }
}
