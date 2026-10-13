@preconcurrency import AVFoundation

/// Streams the default input device as 16 kHz mono Float32 chunks stamped with their capture time.
@MainActor
final class MicrophoneCapture {
    private let engine = AVAudioEngine()
    private var continuation: AsyncStream<AudioChunk>.Continuation?
    private var configurationObserver: NSObjectProtocol?

    var isRunning: Bool { continuation != nil }

    static func requestPermission() async -> Bool {
        switch AVCaptureDevice.authorizationStatus(for: .audio) {
        case .authorized: true
        case .notDetermined: await AVCaptureDevice.requestAccess(for: .audio)
        default: false
        }
    }

    func start() throws -> AsyncStream<AudioChunk> {
        stop()
        let (stream, continuation) = AsyncStream<AudioChunk>.makeStream(bufferingPolicy: .bufferingNewest(128))
        self.continuation = continuation
        do {
            try installTapAndStart(continuation: continuation)
        } catch {
            stop()
            throw error
        }
        configurationObserver = NotificationCenter.default.addObserver(
            forName: .AVAudioEngineConfigurationChange, object: engine, queue: .main
        ) { [weak self] _ in
            MainActor.assumeIsolated { self?.restartAfterDeviceChange() }
        }
        return stream
    }

    func stop() {
        if let configurationObserver { NotificationCenter.default.removeObserver(configurationObserver) }
        configurationObserver = nil
        engine.inputNode.removeTap(onBus: 0)
        engine.stop()
        continuation?.finish()
        continuation = nil
    }

    private func installTapAndStart(continuation: AsyncStream<AudioChunk>.Continuation) throws {
        let input = engine.inputNode
        let format = input.outputFormat(forBus: 0)
        guard format.sampleRate > 0, format.channelCount > 0 else { throw AudioError.noInputDevice }
        let resampler = try StreamingResampler(inputFormat: format)
        input.installTap(onBus: 0, bufferSize: 4096, format: format,
                         block: Self.makeTapBlock(resampler: resampler, continuation: continuation))
        engine.prepare()
        try engine.start()
        Log.audio.info("Microphone started: \(format.sampleRate, privacy: .public) Hz, \(format.channelCount) ch")
    }

    private func restartAfterDeviceChange() {
        guard let continuation else { return }
        Log.audio.info("Audio configuration changed; restarting microphone")
        engine.inputNode.removeTap(onBus: 0)
        engine.stop()
        do {
            try installTapAndStart(continuation: continuation)
        } catch {
            Log.audio.error("Microphone restart failed: \(error.localizedDescription, privacy: .public)")
            stop()
        }
    }

    /// Built outside the main actor: the tap runs on a real-time audio thread.
    private nonisolated static func makeTapBlock(
        resampler: StreamingResampler,
        continuation: AsyncStream<AudioChunk>.Continuation
    ) -> AVAudioNodeTapBlock {
        { buffer, when in
            do {
                let samples = try resampler.convert(buffer)
                let hostTime = when.isHostTimeValid ? when.hostTime : mach_absolute_time()
                if !samples.isEmpty { continuation.yield(AudioChunk(samples: samples, hostTime: hostTime)) }
            } catch {
                Log.audio.error("Resampling failed: \(error.localizedDescription, privacy: .public)")
            }
        }
    }
}
