import Foundation

/// A hosted, OpenAI-compatible `/audio/transcriptions` service. The recording of a request leaves the Mac.
public struct CloudTranscription: Sendable, Hashable {
    /// The chat service whose key it shares: one key per company.
    public let service: ModelAPI
    public let model: String

    public static let openAI = CloudTranscription(server: .openAI, model: "gpt-4o-mini-transcribe")
    /// Groq bills at least ten seconds per request, which adds up with short commands.
    public static let groq = CloudTranscription(server: .groq, model: "whisper-large-v3-turbo")

    private init(server: LocalModelChoice.Server, model: String) {
        // Both servers are API presets; the force unwrap is checked by the tests.
        service = server.api!
        self.model = model
    }

    public var url: URL { service.baseURL.appending(path: "audio/transcriptions") }

    /// A multipart form with the recording as a WAV file, the model and the language (ISO 639-1).
    public func request(samples: [Float], sampleRate: Int, language: String, apiKey: String, boundary: String) -> (headers: [String: String], body: Data) {
        var body = Data()
        func field(_ name: String, _ value: String) {
            body.append(Data("--\(boundary)\r\nContent-Disposition: form-data; name=\"\(name)\"\r\n\r\n\(value)\r\n".utf8))
        }
        field("model", model)
        field("language", language)
        field("response_format", "json")
        body.append(Data("--\(boundary)\r\nContent-Disposition: form-data; name=\"file\"; filename=\"speech.wav\"\r\nContent-Type: audio/wav\r\n\r\n".utf8))
        body.append(WAVFile.pcm16(samples, sampleRate: sampleRate))
        body.append(Data("\r\n--\(boundary)--\r\n".utf8))
        return (["Authorization": "Bearer \(apiKey)", "Content-Type": "multipart/form-data; boundary=\(boundary)"], body)
    }

    public static func text(inResponse data: Data) throws -> String {
        guard let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let text = object["text"] as? String else { throw ModelAPIError.unexpectedResponse }
        return text.trimmingCharacters(in: .whitespacesAndNewlines)
    }
}

public enum WAVFile {
    /// Mono 16-bit PCM; samples outside -1...1 are clipped.
    public static func pcm16(_ samples: [Float], sampleRate: Int) -> Data {
        let dataSize = samples.count * 2
        var out = Data(capacity: 44 + dataSize)
        func append<T: FixedWidthInteger>(_ value: T) { withUnsafeBytes(of: value.littleEndian) { out.append(contentsOf: $0) } }
        out.append(Data("RIFF".utf8))
        append(UInt32(36 + dataSize))
        out.append(Data("WAVEfmt ".utf8))
        append(UInt32(16))
        append(UInt16(1))
        append(UInt16(1))
        append(UInt32(sampleRate))
        append(UInt32(sampleRate * 2))
        append(UInt16(2))
        append(UInt16(16))
        out.append(Data("data".utf8))
        append(UInt32(dataSize))
        for sample in samples {
            append(Int16(max(-1, min(1, sample)) * Float(Int16.max)))
        }
        return out
    }
}
