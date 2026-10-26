import Foundation
import Testing
@testable import AsistanCore

@Suite("Whisper's invented sentences and quiet recordings")
struct MadeUpSentencesTests {
    @Test("the closing lines of videos are dropped", arguments: [
        "Altyazı M.K.", "altyazı m.k", "Altyazı: Ahmet Yılmaz", "ALTYAZI: M.K.", "İzlediğiniz için teşekkür ederim.",
        "Abone olmayı unutmayın!", "Thanks for watching!", "Thank you for watching.",
        "Subtitles by the Amara.org community", "Transcribed by ESO, translated by —", "you", "You.",
    ])
    func dropsInventedLines(text: String) {
        #expect(MadeUpSentences.isMadeUp(text))
        #expect(MadeUpSentences.removed(from: text).isEmpty)
    }

    @Test("what people actually say stays", arguments: [
        "Teşekkürler.", "Thank you.", "Altyazıyı aç", "altyazı aç", "Bilge, çeviri yap",
        "Bilge, YouTube'da izlediğim videoyu aç", "you know what time it is", "Subscribe me to the newsletter",
    ])
    func keepsRealSpeech(text: String) {
        #expect(MadeUpSentences.removed(from: text) == text)
    }

    @Test("only the invented sentence is taken out")
    func dropsOnlyTheInventedSentence() {
        #expect(MadeUpSentences.removed(from: "Bilge, saat kaç? Altyazı M.K.") == "Bilge, saat kaç?")
        #expect(MadeUpSentences.removed(from: "Thanks for watching! Bilge, stop.") == "Bilge, stop.")
    }

    private let rate = 16_000.0

    private func noise(_ seconds: Double, _ amplitude: Float, seed: UInt64 = 1) -> [Float] {
        var state = seed
        return (0..<Int(seconds * rate)).map { _ in
            state = state &* 6364136223846793005 &+ 1442695040888963407
            return (Float(state >> 40) / Float(1 << 24) * 2 - 1) * amplitude
        }
    }

    private func tone(_ seconds: Double, _ amplitude: Float) -> [Float] {
        (0..<Int(seconds * rate)).map { amplitude * sin(2 * .pi * 220 * Float($0) / Float(rate)) }
    }

    @Test("a voice over room noise is kept")
    func keepsAVoice() {
        let voice = zip(tone(0.8, 0.1), noise(0.8, 0.002, seed: 2)).map(+)
        #expect(Loudness.holdsSpeech(noise(0.5, 0.002) + voice + noise(0.6, 0.002, seed: 3), sampleRate: rate))
    }

    @Test("a quiet voice is kept when the room is quieter")
    func keepsAQuietVoice() {
        #expect(Loudness.holdsSpeech(noise(0.5, 0.0005) + tone(0.6, 0.014) + noise(0.5, 0.0005, seed: 4), sampleRate: rate))
    }

    @Test("steady noise, near silence and clicks are dropped")
    func dropsNoise() {
        #expect(!Loudness.holdsSpeech(noise(2, 0.3), sampleRate: rate))
        #expect(!Loudness.holdsSpeech(noise(0.5, 0.0001) + tone(0.6, 0.0015) + noise(0.5, 0.0001, seed: 5), sampleRate: rate))
        #expect(!Loudness.holdsSpeech(noise(0.6, 0.001) + tone(0.1, 0.3) + noise(0.6, 0.001, seed: 6), sampleRate: rate))
        #expect(!Loudness.holdsSpeech([], sampleRate: rate))
        #expect(!Loudness.holdsSpeech([Float](repeating: 0, count: 16_000), sampleRate: rate))
    }
}
