@preconcurrency import AVFoundation

/// Plays queued mono buffers back-to-back and lets callers await until everything queued has been heard.
@MainActor
final class AudioPlayer {
    private let engine = AVAudioEngine()
    private let node = AVAudioPlayerNode()
    private let format: AVAudioFormat
    private var outstandingBuffers = 0
    private var drainWaiters: [CheckedContinuation<Void, Never>] = []
    private var generation = 0

    init(sampleRate: Double) {
        guard let format = AVAudioFormat(standardFormatWithSampleRate: sampleRate, channels: 1) else {
            preconditionFailure("Mono float format at \(sampleRate) Hz must be constructible")
        }
        self.format = format
        engine.attach(node)
        engine.connect(node, to: engine.mainMixerNode, format: format)
    }

    var isPlaying: Bool { outstandingBuffers > 0 }

    var isMuted: Bool {
        get { node.volume == 0 }
        set { node.volume = newValue ? 0 : 1 }
    }

    func enqueue(_ samples: [Float]) throws {
        guard !samples.isEmpty else { return }
        let buffer = try PCMBuffers.mono(samples, sampleRate: format.sampleRate)

        if !engine.isRunning {
            engine.prepare()
            try engine.start()
        }
        outstandingBuffers += 1
        let scheduledGeneration = generation
        node.scheduleBuffer(buffer, completionCallbackType: .dataPlayedBack) { [weak self] _ in
            Task { @MainActor in self?.bufferFinished(generation: scheduledGeneration) }
        }
        if !node.isPlaying { node.play() }
    }

    func waitUntilDrained() async {
        guard outstandingBuffers > 0 else { return }
        await withCheckedContinuation { drainWaiters.append($0) }
    }

    /// Cuts playback immediately (e.g. the user starts talking) and releases anyone waiting.
    func stop() {
        generation += 1
        node.stop()
        outstandingBuffers = 0
        resumeWaiters()
    }

    private func bufferFinished(generation finishedGeneration: Int) {
        guard finishedGeneration == generation else { return }
        outstandingBuffers = max(0, outstandingBuffers - 1)
        if outstandingBuffers == 0 { resumeWaiters() }
    }

    private func resumeWaiters() {
        let waiters = drainWaiters
        drainWaiters.removeAll()
        waiters.forEach { $0.resume() }
    }
}
