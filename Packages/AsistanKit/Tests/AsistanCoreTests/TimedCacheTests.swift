import Foundation
import Testing
@testable import AsistanCore

@Suite("TimedCache")
struct TimedCacheTests {
    @Test("fresh within its lifetime, kept afterwards for a stale answer")
    func lifetime() {
        let start = Date(timeIntervalSince1970: 1_000_000)
        var cache = TimedCache<String, Int>(lifetime: 600)
        cache.store(42, for: "gold", at: start)
        #expect(cache.fresh("gold", at: start.addingTimeInterval(599)) == 42)
        #expect(cache.fresh("gold", at: start.addingTimeInterval(600)) == nil)
        #expect(cache.any("gold")?.value == 42)
        #expect(cache.any("fuel") == nil)
    }

    @Test("spoken durations and the stale note")
    func durations() {
        #expect(SpokenDuration.text(minutes: 65, language: .turkish) == "1 saat 5 dakika")
        #expect(SpokenDuration.text(minutes: 120, language: .english) == "2 hours")
        #expect(SpokenDuration.text(minutes: 0, language: .turkish) == "bir dakikadan az")
        #expect(SpokenDuration.staleNote(age: 25 * 60, language: .turkish) == " Güncel veriye ulaşamadım; bu bilgi 25 dakika önceki.")
    }
}
