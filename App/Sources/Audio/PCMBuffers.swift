@preconcurrency import AVFoundation

enum PCMBuffers {
    static func mono16k(_ samples: [Float]) throws -> AVAudioPCMBuffer {
        try mono(samples, sampleRate: StreamingResampler.targetSampleRate)
    }

    static func mono(_ samples: [Float], sampleRate: Double) throws -> AVAudioPCMBuffer {
        guard let format = AVAudioFormat(standardFormatWithSampleRate: sampleRate, channels: 1),
              let buffer = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: AVAudioFrameCount(max(samples.count, 1))),
              let channel = buffer.floatChannelData?[0]
        else { throw AudioError.invalidFormat }
        samples.withUnsafeBufferPointer { pointer in
            if let base = pointer.baseAddress { channel.update(from: base, count: samples.count) }
        }
        buffer.frameLength = AVAudioFrameCount(samples.count)
        return buffer
    }

    /// One-shot conversion of a complete buffer (sample rate, channel count and sample type).
    static func convert(_ buffer: AVAudioPCMBuffer, to format: AVAudioFormat) throws -> AVAudioPCMBuffer {
        if buffer.format == format { return buffer }
        guard let converter = AVAudioConverter(from: buffer.format, to: format) else {
            throw AudioError.converterUnavailable
        }
        let ratio = format.sampleRate / buffer.format.sampleRate
        let capacity = AVAudioFrameCount(Double(buffer.frameLength) * ratio) + 64
        guard let output = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: capacity) else {
            throw AudioError.invalidFormat
        }
        var consumed = false
        var conversionError: NSError?
        let status = converter.convert(to: output, error: &conversionError) { _, inputStatus in
            if consumed {
                inputStatus.pointee = .endOfStream
                return nil
            }
            consumed = true
            inputStatus.pointee = .haveData
            return buffer
        }
        if status == .error {
            throw AudioError.conversionFailed(conversionError?.localizedDescription ?? "bilinmeyen hata")
        }
        return output
    }
}
