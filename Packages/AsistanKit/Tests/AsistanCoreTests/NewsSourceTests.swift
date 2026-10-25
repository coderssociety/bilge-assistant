import AsistanCore
import Foundation
import Testing

@Suite("NewsSource")
struct NewsSourceTests {
    @Test("a named source is found in Turkish and English commands", arguments: [
        ("TRT'den haberleri oku", AssistantLanguage.turkish, NewsSource.trtHaber),
        ("BBC haberleri", .turkish, .bbcTurkish),
        ("AA'dan son başlıklar", .turkish, .anadolu),
        ("Anadolu Ajansı ne diyor", .turkish, .anadolu),
        ("news from the Guardian", .english, .guardian),
        ("BBC headlines", .english, .bbcNews),
        ("what's on NPR", .english, .npr),
    ])
    func named(command: String, language: AssistantLanguage, source: NewsSource) {
        #expect(NewsSource.named(in: command, language: language) == source)
    }

    @Test("other words are not sources", arguments: ["Bugünün haberleri", "aaaa haberleri", "Teknoloji haberleri"])
    func notNamed(command: String) {
        #expect(NewsSource.named(in: command, language: .turkish) == nil)
    }

    @Test("asking for another source", arguments: [
        ("Başka bir kaynak", true), ("farklı bir siteden oku", true), ("diğer kaynaklarda ne var", true),
        ("another source please", true), ("somewhere else", true),
        ("Başka var mı", false), ("bu kaynak güvenilir mi", false), ("başka haber", false),
    ])
    func another(command: String, asks: Bool) {
        #expect(NewsSource.asksForAnother(command) == asks)
    }

    @Test("the next source goes round, skipping one without a feed for the topic")
    func next() {
        #expect(NewsSource.anadolu.next(for: .general) == .trtHaber)
        #expect(NewsSource.trtHaber.next(for: .general) == .bbcTurkish)
        #expect(NewsSource.bbcTurkish.next(for: .general) == .anadolu)
        #expect(NewsSource.trtHaber.next(for: .technology) == .anadolu)
        #expect(NewsSource.npr.next(for: .sports) == .bbcNews)
    }

    @Test("every source of a language has a general feed, over https")
    func feeds() {
        for source in NewsSource.allCases {
            #expect(source.feed(.general)?.scheme == "https")
        }
        #expect(NewsSource.trtHaber.feed(.technology)?.absoluteString == "https://www.trthaber.com/bilim_teknoloji_articles.rss")
        #expect(NewsSource.bbcTurkish.feed(.sports) == nil)
    }
}
