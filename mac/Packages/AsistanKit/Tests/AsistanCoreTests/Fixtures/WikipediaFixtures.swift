import Foundation

/// Trimmed responses saved from the live sources on 25 October 2026.
enum WikipediaFixtures {
    static let wikipediaSummary = Data(#"""
    {"type":"standard","title":"Fotosentez","displaytitle":"<span class=\"mw-page-title-main\">Fotosentez</span>","lang":"tr","extract":"Fotosentez, bitkiler ve diğer canlılar tarafından, ışık enerjisini kimyasal enerjiye dönüştürmek için kullanılan bir işlemdir. Bu kimyasal enerji, karbondioksit ve sudan sentezlenen şekerler gibi karbonhidrat moleküllerinde depolanır."}
    """#.utf8)

    static let wikipediaDisambiguation = Data(#"""
    {"type":"disambiguation","title":"Ankara (anlam ayrımı)","extract":"Ankara, Türkiye'nin başkenti ve en kalabalık ikinci şehridir. Ankara sözcüğü ile ayrıca şunlardan biri kastedilmiş olabilir;"}
    """#.utf8)

    static let wikipediaOpenSearch = Data(#"""
    ["atatürk",["Atatürk","Atatürk Havalimanı","Atatürk Olimpiyat Stadyumu"],["","",""],["https://tr.wikipedia.org/wiki/Atat%C3%BCrk","https://tr.wikipedia.org/wiki/Atat%C3%BCrk_Havaliman%C4%B1","https://tr.wikipedia.org/wiki/Atat%C3%BCrk_Olimpiyat_Stadyumu"]]
    """#.utf8)
}
