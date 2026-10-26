@preconcurrency import AVFoundation
import AsistanCore

enum AudioFileError: LocalizedError {
    case noAudio
    case unreadable

    var errorDescription: String? {
        switch self {
        case .noAudio: String(localized: "Bu dosyada ses yok.")
        case .unreadable: String(localized: "Bu ses dosyasını okuyamadım.")
        }
    }
}

/// "Bu ses dosyasını yazıya dök": decodes an audio or video file (m4a, mp3, wav, mp4…) to 16 kHz mono with
/// AVFoundation and transcribes it in fixed chunks, each stamped with where it starts. Only one chunk of audio
/// is held at a time.
enum AudioFileTranscriber {
    static let chunkDuration: TimeInterval = 30

    struct Transcript: Sendable {
        let chunks: [TranscriptChunk]
        let duration: TimeInterval
    }

    static func transcribe(_ file: URL, with recognizer: any SpeechRecognizer) async throws -> Transcript {
        let sampleRate = StreamingResampler.targetSampleRate
        let asset = AVURLAsset(url: file)
        guard let track = try await asset.loadTracks(withMediaType: .audio).first else { throw AudioFileError.noAudio }
        let reader = try AVAssetReader(asset: asset)
        let output = AVAssetReaderTrackOutput(track: track, outputSettings: [
            AVFormatIDKey: kAudioFormatLinearPCM,
            AVSampleRateKey: sampleRate,
            AVNumberOfChannelsKey: 1,
            AVLinearPCMBitDepthKey: 32,
            AVLinearPCMIsFloatKey: true,
            AVLinearPCMIsNonInterleaved: false,
            AVLinearPCMIsBigEndianKey: false,
        ])
        guard reader.canAdd(output) else { throw AudioFileError.unreadable }
        let provider = reader.outputProvider(for: output)
        try reader.start()
        defer { reader.cancelReading() }

        let chunkLength = Int(chunkDuration * sampleRate)
        var pending: [Float] = []
        var chunks: [TranscriptChunk] = []
        var transcribedSamples = 0
        while let buffer = try await provider.next() {
            try Task.checkCancellation()
            pending += buffer.withUnsafeSampleBuffer { samples(of: $0) }
            while pending.count >= chunkLength {
                let piece = Array(pending.prefix(chunkLength))
                pending = Array(pending.dropFirst(chunkLength))
                chunks += try await transcribed(piece, startingAt: Double(transcribedSamples) / sampleRate, with: recognizer)
                transcribedSamples += piece.count
            }
        }
        if !pending.isEmpty {
            chunks += try await transcribed(pending, startingAt: Double(transcribedSamples) / sampleRate, with: recognizer)
            transcribedSamples += pending.count
        }
        return Transcript(chunks: chunks, duration: Double(transcribedSamples) / sampleRate)
    }

    private static func transcribed(_ samples: [Float], startingAt offset: TimeInterval,
                                    with recognizer: any SpeechRecognizer) async throws -> [TranscriptChunk] {
        let text = try await recognizer.transcribe(samples).trimmingCharacters(in: .whitespacesAndNewlines)
        return text.isEmpty ? [] : [TranscriptChunk(offset: offset, text: text)]
    }

    private static func samples(of buffer: CMSampleBuffer) -> [Float] {
        guard let block = CMSampleBufferGetDataBuffer(buffer) else { return [] }
        let count = CMBlockBufferGetDataLength(block) / MemoryLayout<Float>.size
        guard count > 0 else { return [] }
        var samples = [Float](repeating: 0, count: count)
        let status = samples.withUnsafeMutableBytes { bytes -> OSStatus in
            guard let destination = bytes.baseAddress else { return kCMBlockBufferBadPointerParameterErr }
            return CMBlockBufferCopyDataBytes(block, atOffset: 0, dataLength: bytes.count, destination: destination)
        }
        return status == kCMBlockBufferNoErr ? samples : []
    }
}
