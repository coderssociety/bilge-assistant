import Testing
@testable import AsistanCore

@Suite("BargeInDetector")
struct BargeInDetectorTests {
    let detector = BargeInDetector(matcher: WakePhraseMatcher(phrase: "Bilge"))
    let reply = "İstanbul, Boğaz'ın iki yakasına kurulmuş, binlerce yıllık tarihi olan bir şehirdir. Müzik durduruldu."

    @Test("the assistant's own words leaking back are ignored", arguments: [
        "İstanbul Boğaz'ın iki yakasına kurulmuş",
        "binlerce yıllık tarihi olan bir şehir",
        "müzik durduruldu",
        "",
    ])
    func echo(heard: String) {
        #expect(detector.evaluate(heard: heard, speaking: reply) == .none)
    }

    @Test("wake phrase or a short stop word stops the reply", arguments: [
        "Bilge dur", "Bilge", "dur", "Sus!", "yeter", "tamam tamam", "Bilge, yeter artık",
        "İstanbul Boğaz'ın dur",
    ])
    func stop(heard: String) {
        #expect(detector.evaluate(heard: heard, speaking: reply) == .stop)
    }

    @Test("wake phrase with a new request interrupts and runs it")
    func newCommand() {
        #expect(detector.evaluate(heard: "Bilge, saat kaç", speaking: reply) == .command("saat kaç"))
        #expect(detector.evaluate(heard: "yıllık tarihi Bilge sesi kıs", speaking: reply) == .command("sesi kıs"))
    }

    @Test("a stop word the assistant itself is saying is echo, not the user")
    func stopWordInReply() {
        #expect(detector.evaluate(heard: "tamam Safari'yi açtım", speaking: "Tamam, Safari'yi açtım.") == .none)
        #expect(detector.evaluate(heard: "Bilge dur", speaking: "Tamam, Safari'yi açtım.") == .stop)
        #expect(detector.evaluate(heard: "ben bilge", speaking: "Ben Bilge, senin asistanınım.") == .none)
        #expect(detector.evaluate(heard: "bilge dur", speaking: "Ben Bilge, senin asistanınım.") == .stop)
    }

    @Test("ordinary speech without a stop intent is not an interruption", arguments: [
        "evet çok güzel bir şehir anlatıyorsun", "yemek hazır mı",
    ])
    func unrelated(heard: String) {
        #expect(detector.evaluate(heard: heard, speaking: reply) == .none)
    }
}
