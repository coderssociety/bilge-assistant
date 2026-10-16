import AsistanCore
import Foundation
import Testing

@Suite("NewsRequest")
struct NewsRequestTests {
    @Test("the topic is read from the command's words", arguments: [
        ("Teknoloji haberlerinden başlık var mı", NewsRequest.Topic.technology),
        ("bilim dünyasından ne var", .technology),
        ("Ekonomi haberleri", .economy),
        ("borsada bugün ne oldu", .economy),
        ("Spor haberlerini oku", .sports),
        ("dünyadan haberler", .world),
        ("What's new in tech?", .technology),
        ("latest business news", .economy),
        ("gündemde ne var", .general),
    ])
    func topic(command: String, topic: NewsRequest.Topic) {
        #expect(NewsRequest.topic(in: command) == topic)
    }

    @Test("a request that names no topic has none")
    func noTopic() {
        #expect(NewsRequest.topic(in: "Bugünün önemli haberleri var mı") == nil)
    }

    @Test("a follow-up that asks neither for news nor a topic continues", arguments: [
        ("Bu kadar mı", true), ("başka var mı", true), ("Is that all?", true),
        ("Bugünün önemli haberleri var mı", false), ("son başlıklar", false), ("spor", false),
    ])
    func continuation(command: String, continues: Bool) {
        #expect(NewsRequest.isContinuation(command) == continues)
    }
}

@Suite("HeadlineMemory")
struct HeadlineMemoryTests {
    let start = Date(timeIntervalSince1970: 1_000)
    let feed = (1...12).map { RSSHeadlines.Item(title: "Başlık \($0)", link: nil) }

    @Test("asking again goes on with the headlines not yet read")
    func continues() {
        var memory = HeadlineMemory()
        #expect(memory.next(feed, topic: "general", count: 5, at: start) == .init(items: Array(feed[0..<5]), kind: .first))
        let second = memory.next(feed, topic: "general", count: 5, at: start.addingTimeInterval(30))
        #expect(second == .init(items: Array(feed[5..<10]), kind: .next))
    }

    @Test("a newer headline at the top is read first")
    func newerFirst() {
        var memory = HeadlineMemory()
        _ = memory.next(feed, topic: "general", count: 5, at: start)
        let newer = RSSHeadlines.Item(title: "Yeni", link: nil)
        let reading = memory.next([newer] + feed, topic: "general", count: 5, at: start.addingTimeInterval(60))
        #expect(reading.items == [newer] + Array(feed[5..<9]))
    }

    @Test("with nothing new left, the latest are read again and said to be the same")
    func repeats() {
        var memory = HeadlineMemory()
        let short = Array(feed.prefix(3))
        _ = memory.next(short, topic: "general", count: 5, at: start)
        #expect(memory.next(short, topic: "general", count: 5, at: start.addingTimeInterval(10)) ==
            .init(items: short, kind: .again))
    }

    @Test("topics are remembered apart, and the memory fades")
    func separateAndFading() {
        var memory = HeadlineMemory()
        _ = memory.next(feed, topic: "general", count: 5, at: start)
        #expect(memory.next(feed, topic: "technology", count: 5, at: start).items == Array(feed[0..<5]))
        let later = start.addingTimeInterval(HeadlineMemory.lifetime + 1)
        #expect(memory.next(feed, topic: "general", count: 5, at: later).items == Array(feed[0..<5]))
    }

    @Test("the topic just read is remembered for a follow-up for a few minutes")
    func recentTopic() {
        var memory = HeadlineMemory()
        _ = memory.next(feed, topic: "technology", count: 5, at: start)
        #expect(memory.recentTopic(at: start.addingTimeInterval(60)) == "technology")
        #expect(memory.recentTopic(at: start.addingTimeInterval(HeadlineMemory.continuationWindow + 1)) == nil)
    }

    @Test("what was read is kept for a later request about one of the headlines, the last reading first")
    func heard() {
        var memory = HeadlineMemory()
        _ = memory.next(feed, topic: "general", count: 2, at: start)
        _ = memory.next(feed, topic: "general", count: 2, at: start.addingTimeInterval(10))
        let heard = memory.heardItems(at: start.addingTimeInterval(20))
        #expect(heard.lastReading == Array(feed[2..<4]))
        #expect(heard.all == Array(feed[2..<4]) + Array(feed[0..<2]))
        #expect(memory.heardItems(at: start.addingTimeInterval(HeadlineMemory.lifetime + 11)).all.isEmpty)
    }
}
