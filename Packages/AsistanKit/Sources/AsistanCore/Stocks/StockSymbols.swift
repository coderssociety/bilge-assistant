import Foundation

public struct StockSymbol: Sendable, Equatable {
    /// Yahoo Finance's symbol: "THYAO.IS", "XU100.IS".
    public let ticker: String
    /// As spoken: "Türk Hava Yolları", "BIST 100".
    public let name: String
    public let isIndex: Bool
    /// Folded names people say, the ticker's letters included.
    let aliases: [String]
    private let englishName: String?

    init(_ ticker: String, _ name: String, english: String? = nil, isIndex: Bool = false, aliases: [String]) {
        self.ticker = ticker
        self.name = name
        englishName = english
        self.isIndex = isIndex
        self.aliases = aliases
    }

    public func spokenName(_ language: AssistantLanguage) -> String {
        language == .english ? englishName ?? name : name
    }
}

/// Borsa İstanbul indices and widely followed companies, by the names people use.
public enum StockSymbols {
    public static let bist100 = StockSymbol("XU100.IS", "BIST 100", isIndex: true,
                                            aliases: ["bist 100", "bist yuz", "bist100", "xu100", "borsa istanbul 100"])

    public static let all: [StockSymbol] = [
        bist100,
        StockSymbol("XU030.IS", "BIST 30", isIndex: true, aliases: ["bist 30", "bist otuz", "bist30", "xu030"]),
        StockSymbol("XBANK.IS", "BIST Bankacılık", english: "BIST Banks", isIndex: true, aliases: ["bankacilik endeksi", "banka endeksi", "xbank"]),
        StockSymbol("THYAO.IS", "Türk Hava Yolları", english: "Turkish Airlines", aliases: ["thy", "thyao", "turk hava yollari", "turkish airlines"]),
        StockSymbol("ASELS.IS", "Aselsan", aliases: ["aselsan", "asels"]),
        StockSymbol("GARAN.IS", "Garanti BBVA", aliases: ["garanti", "garan"]),
        StockSymbol("AKBNK.IS", "Akbank", aliases: ["akbank", "akbnk"]),
        StockSymbol("YKBNK.IS", "Yapı Kredi", aliases: ["yapi kredi", "ykbnk"]),
        StockSymbol("ISCTR.IS", "İş Bankası", english: "Isbank", aliases: ["is bankasi", "isbank", "isctr"]),
        StockSymbol("HALKB.IS", "Halkbank", aliases: ["halkbank", "halk bankasi", "halkb"]),
        StockSymbol("VAKBN.IS", "VakıfBank", aliases: ["vakifbank", "vakif bank", "vakbn"]),
        StockSymbol("KCHOL.IS", "Koç Holding", aliases: ["koc holding", "kchol"]),
        StockSymbol("SAHOL.IS", "Sabancı Holding", aliases: ["sabanci", "sahol"]),
        StockSymbol("EREGL.IS", "Ereğli Demir Çelik", aliases: ["eregli", "erdemir", "eregl"]),
        StockSymbol("KRDMD.IS", "Kardemir", aliases: ["kardemir", "krdmd"]),
        StockSymbol("TUPRS.IS", "Tüpraş", aliases: ["tupras", "tuprs"]),
        StockSymbol("BIMAS.IS", "BİM", aliases: ["bim", "bimas"]),
        StockSymbol("MGROS.IS", "Migros", aliases: ["migros", "mgros"]),
        StockSymbol("SISE.IS", "Şişecam", aliases: ["sisecam", "sise"]),
        StockSymbol("FROTO.IS", "Ford Otosan", aliases: ["ford otosan", "froto"]),
        StockSymbol("TOASO.IS", "Tofaş", aliases: ["tofas", "toaso"]),
        StockSymbol("PGSUS.IS", "Pegasus", aliases: ["pegasus", "pgsus"]),
        StockSymbol("TCELL.IS", "Turkcell", aliases: ["turkcell", "tcell"]),
        StockSymbol("TTKOM.IS", "Türk Telekom", aliases: ["turk telekom", "ttkom"]),
        StockSymbol("ARCLK.IS", "Arçelik", aliases: ["arcelik", "arclk"]),
        StockSymbol("PETKM.IS", "Petkim", aliases: ["petkim", "petkm"]),
        StockSymbol("SASA.IS", "Sasa", aliases: ["sasa"]),
        StockSymbol("HEKTS.IS", "Hektaş", aliases: ["hektas", "hekts"]),
        StockSymbol("ASTOR.IS", "Astor", aliases: ["astor"]),
        StockSymbol("KONTR.IS", "Kontrolmatik", aliases: ["kontrolmatik", "kontr"]),
        StockSymbol("ENKAI.IS", "Enka İnşaat", aliases: ["enka", "enkai"]),
        StockSymbol("TAVHL.IS", "TAV Havalimanları", aliases: ["tav havalimanlari", "tavhl"]),
        StockSymbol("CCOLA.IS", "Coca-Cola İçecek", aliases: ["coca cola icecek", "ccola"]),
        StockSymbol("AEFES.IS", "Anadolu Efes", aliases: ["anadolu efes", "aefes"]),
        StockSymbol("ULKER.IS", "Ülker", aliases: ["ulker"]),
        StockSymbol("EKGYO.IS", "Emlak Konut", aliases: ["emlak konut", "ekgyo"]),
        StockSymbol("OTKAR.IS", "Otokar", aliases: ["otokar", "otkar"]),
        StockSymbol("TTRAK.IS", "Türk Traktör", aliases: ["turk traktor", "ttrak"]),
        StockSymbol("VESTL.IS", "Vestel", aliases: ["vestel", "vestl"]),
        StockSymbol("DOAS.IS", "Doğuş Otomotiv", aliases: ["dogus otomotiv", "doas"]),
        StockSymbol("GUBRF.IS", "Gübre Fabrikaları", aliases: ["gubretas", "gubre fabrikalari", "gubrf"]),
        StockSymbol("KOZAL.IS", "Koza Altın", aliases: ["koza altin", "kozal"]),
        StockSymbol("MAVI.IS", "Mavi", aliases: ["mavi giyim"]),
        StockSymbol("LOGO.IS", "Logo Yazılım", aliases: ["logo yazilim"]),
        StockSymbol("ALARK.IS", "Alarko Holding", aliases: ["alarko", "alark"]),
        StockSymbol("DOHOL.IS", "Doğan Holding", aliases: ["dogan holding", "dohol"]),
    ]

    /// The symbols named in a request, in the order said; ticker letters count only as whole words.
    public static func named(in text: String) -> [StockSymbol] {
        let folded = " " + TurkishText.folded(text) + " "
        let words = folded.split(separator: " ").map(String.init)
        let found = all.compactMap { symbol -> (StockSymbol, String.Index)? in
            let positions = symbol.aliases.compactMap { position(of: $0, in: folded, words: words) }
            return positions.min().map { (symbol, $0) }
        }
        return found.sorted { $0.1 < $1.1 }.map(\.0)
    }

    /// Where `alias` starts as a word, allowing a Turkish ending on a name of more than three letters
    /// ("Aselsan'ın", "THY'nin" are single words once folded).
    private static func position(of alias: String, in folded: String, words: [String]) -> String.Index? {
        if alias.contains(" ") { return folded.range(of: " " + alias + " ")?.lowerBound ?? folded.range(of: " " + alias)?.lowerBound }
        let endings: Set<String> = ["", "nin", "in", "un", "nun", "a", "e", "ya", "ye", "da", "de", "ta", "te", "i", "yi", "u", "yu"]
        guard let word = words.first(where: { word in
            word.hasPrefix(alias) && (endings.contains(String(word.dropFirst(alias.count)))
                || (alias.count > 3 && word.count - alias.count <= 4))
        }) else { return nil }
        return folded.range(of: " " + word + " ")?.lowerBound
    }
}
