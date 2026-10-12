@preconcurrency import AVFoundation

enum AudioError: LocalizedError {
    case noInputDevice
    case converterUnavailable
    case conversionFailed(String)
    case invalidFormat

    var errorDescription: String? {
        switch self {
        case .noInputDevice: "Kullanılabilir bir mikrofon bulunamadı."
        case .converterUnavailable: "Ses dönüştürücü oluşturulamadı."
        case let .conversionFailed(reason): "Ses dönüştürülemedi: \(reason)"
        case .invalidFormat: "Desteklenmeyen ses biçimi."
        }
    }
}

/// Converts microphone buffers to 16 kHz mono Float32 with one persistent converter,
/// so filter state carries across buffers instead of clicking at every chunk boundary.
/// Only ever used from the single audio tap thread.
final class StreamingResampler: @unchecked Sendable {
    static let targetSampleRate: Double = 16_000

    private let converter: AVAudioConverter
    private let outputFormat: AVAudioFormat

    init(inputFormat: AVAudioFormat) throws {
        guard let outputFormat = AVAudioFormat(
            commonFormat: .pcmFormatFloat32, sampleRate: Self.targetSampleRate, channels: 1, interleaved: false)
        else { throw AudioError.invalidFormat }
        guard let converter = AVAudioConverter(from: inputFormat, to: outputFormat) else {
            throw AudioError.converterUnavailable
        }
        self.converter = converter
        self.outputFormat = outputFormat
    }

    func convert(_ buffer: AVAudioPCMBuffer) throws -> [Float] {
        let ratio = outputFormat.sampleRate / buffer.format.sampleRate
        let capacity = AVAudioFrameCount(Double(buffer.frameLength) * ratio) + 32
        guard let output = AVAudioPCMBuffer(pcmFormat: outputFormat, frameCapacity: capacity) else {
            throw AudioError.invalidFormat
        }
        var consumed = false
        var conversionError: NSError?
        let status = converter.convert(to: output, error: &conversionError) { _, inputStatus in
            if consumed {
                inputStatus.pointee = .noDataNow
                return nil
            }
            consumed = true
            inputStatus.pointee = .haveData
            return buffer
        }
        if status == .error {
            throw AudioError.conversionFailed(conversionError?.localizedDescription ?? "bilinmeyen hata")
        }
        guard let channel = output.floatChannelData?[0] else { return [] }
        return Array(UnsafeBufferPointer(start: channel, count: Int(output.frameLength)))
    }
}
