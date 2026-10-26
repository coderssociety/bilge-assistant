import Foundation
import Testing
@testable import AsistanCore

@Suite("CloudTranscription")
struct CloudTranscriptionTests {
    @Test("shares the chat service's key and posts to its transcription endpoint")
    func presets() {
        #expect(CloudTranscription.openAI.service.server == .openAI)
        #expect(CloudTranscription.groq.service.server == .groq)
        #expect(CloudTranscription.groq.url.absoluteString == "https://api.groq.com/openai/v1/audio/transcriptions")
    }

    @Test("the form carries the model, the language and a WAV file")
    func form() throws {
        let (headers, body) = CloudTranscription.openAI.request(samples: [0, 0.5, -1], sampleRate: 16_000, language: "tr",
                                                                apiKey: "k", boundary: "XYZ")
        #expect(headers["Authorization"] == "Bearer k")
        #expect(headers["Content-Type"] == "multipart/form-data; boundary=XYZ")
        let text = String(decoding: body, as: UTF8.self)
        #expect(text.contains("name=\"model\"\r\n\r\ngpt-4o-mini-transcribe\r\n"))
        #expect(text.contains("name=\"language\"\r\n\r\ntr\r\n"))
        #expect(text.contains("filename=\"speech.wav\"\r\nContent-Type: audio/wav\r\n\r\nRIFF"))
        #expect(text.hasSuffix("\r\n--XYZ--\r\n"))
    }

    @Test("reads the text and rejects other answers")
    func response() throws {
        #expect(try CloudTranscription.text(inResponse: Data(#"{"text":" Bilge, saat kaç? "}"#.utf8)) == "Bilge, saat kaç?")
        #expect(throws: ModelAPIError.unexpectedResponse) { try CloudTranscription.text(inResponse: Data("{}".utf8)) }
    }

    @Test("a WAV file has a 44-byte header and two bytes per clipped sample")
    func wav() {
        let data = WAVFile.pcm16([0, 2, -2], sampleRate: 16_000)
        #expect(data.count == 44 + 6)
        #expect(data.prefix(4) == Data("RIFF".utf8))
        let samples = data.suffix(6).withUnsafeBytes { Array($0.bindMemory(to: Int16.self)) }.map(Int16.init(littleEndian:))
        #expect(samples == [0, Int16.max, -Int16.max])
        let rate = data.subdata(in: 24..<28).withUnsafeBytes { $0.loadUnaligned(as: UInt32.self) }
        #expect(UInt32(littleEndian: rate) == 16_000)
    }
}

@Suite("WakePhraseMatcher.restoring")
struct WakePhraseRestoringTests {
    private let matcher = WakePhraseMatcher(phrase: "Bilge")

    @Test("keeps a transcript that already starts with the phrase")
    func kept() {
        #expect(matcher.restoring("Bilge", in: "Bilge, saat kaç?") == "Bilge, saat kaç?")
    }

    @Test("replaces a respelled name", arguments: [("Bilgé, what time is it", "Bilge, what time is it"),
                                                   ("Bilgi saat kaç", "Bilge, saat kaç")])
    func respelled(heard: String, expected: String) {
        #expect(matcher.restoring("Bilge", in: heard) == expected)
    }

    @Test("puts the phrase in front of a transcript that lost it")
    func lost() {
        #expect(matcher.restoring("Bilge", in: "what time is it") == "Bilge, what time is it")
        #expect(matcher.restoring("Bilge", in: "") == "Bilge")
    }
}
