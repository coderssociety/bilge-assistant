import AsistanCore
import Foundation
import Testing

@Suite("NewsArticleReference")
struct NewsArticleReferenceTests {
    static let reading = [
        "Şanlıurfa'da TEKNOFEST Güneydoğu'da finale yükselen takımlar ödüllendirildi",
        "Tesla, \"havada ilerlemek için yüksek basınçlı hava tankları\" kullanılan yeni aracını tanıttı",
        "Meta'nın iş ilanı algoritmasındaki ayrımcılık Hollanda'da tescillendi",
        "Claude'un \"keşfettiği\" buluş üzerinde yıllardır çalışan biyolog, otonom keşif tanımına şüpheyle yaklaşıyor",
        "Telegram'a yeni özellikler geldi, Claude Code'a da güncelleme",
    ].enumerated().map { RSSHeadlines.Item(title: $1, link: URL(string: "https://www.aa.com.tr/tr/haber/\($0)")) }

    func find(_ command: String) -> NewsArticleReference.Request? {
        NewsArticleReference.find(command, lastReading: Self.reading, all: Self.reading)
    }

    @Test("a headline is found by its words, even misheard", arguments: [
        ("Cloud'un keşfettiği buluşu açar mısın", 3, true),
        ("Tesla'nın yeni aracı haberini anlat", 1, false),
        ("Meta'daki ayrımcılık haberinin detayı ne", 2, false),
        ("tell me more about the Tesla news", 1, false),
    ])
    func byWords(command: String, index: Int, inBrowser: Bool) {
        #expect(find(command) == .init(item: Self.reading[index], inBrowser: inBrowser))
    }

    @Test("a headline is found by its place in the last reading", arguments: [
        ("üçüncü haberi aç", 2), ("ikincisini anlat", 1), ("sonuncusunu oku", 4), ("ilk haberin detayı", 0),
        ("open the second one", 1),
    ])
    func byPlace(command: String, index: Int) {
        #expect(find(command)?.item == Self.reading[index])
    }

    @Test("requests that don't point at a headline are left to the other tools", arguments: [
        "Telegram'ı aç", "Safari'yi aç", "ikinci sekmeyi aç", "Teknoloji haberlerini oku", "son haberleri oku",
        "Bu kadar mı", "ilkbahar haberini aç", "Tesla", "open the last tab", "open the second app", "Claude Code'u aç",
    ])
    func notAnArticle(command: String) {
        #expect(find(command) == nil)
    }

    @Test("nothing is found before any news was read")
    func nothingRead() {
        #expect(NewsArticleReference.find("üçüncü haberi aç", lastReading: [], all: []) == nil)
    }
}
