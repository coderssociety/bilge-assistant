import AsistanCore
import Foundation
import Observation

/// Runs the always-on loop: microphone → VAD → utterance segments → ASR → wake/turn logic → reply → speech.
/// Half duplex: while a reply is being produced or spoken, microphone audio is dropped so the assistant
/// never hears (and answers) itself.
@MainActor
@Observable
final class AssistantController {
    enum Status: Equatable {
        case off
        case loading(String)
        case listening
        case awake
        case transcribing
        case thinking
        case speaking
        case confirming
        case failed(String)
    }

    private static let wakeProbeSeconds = 2.5
    private static let tickInterval = Duration.milliseconds(250)
    private static let confirmationTimeout = Duration.seconds(8)
    private static let confirmationGrace = Duration.seconds(5)

    private(set) var status: Status = .off
    private(set) var lastHeard: String?
    private(set) var lastReply: String?
    private(set) var pendingConfirmation: String?
    var isRunning: Bool { listenTask != nil }

    private let settings: AssistantSettings
    private let speech: SpeechOutput
    private let handler: any CommandHandling
    private let microphone: any AudioSource
    private var vad: VoiceActivityMonitor?
    private var recognizer: (any SpeechRecognizer)?
    private var flow: ConversationFlow
    private var segmenter = SpeechSegmenter(configuration: .init(chunkDuration: VoiceActivityFrame.duration, minSilence: 0.6))
    private var segmentQueue: AsyncStream<SpeechSegmenter.Segment>.Continuation?
    private var listenTask: Task<Void, Never>?
    private var segmentTask: Task<Void, Never>?
    private var tickTask: Task<Void, Never>?
    private var turnTask: Task<Void, Never>?
    private var isAudioSuspended = false
    private var confirmationContinuation: CheckedContinuation<ConfirmationParser.Answer, Never>?

    init(settings: AssistantSettings, speech: SpeechOutput, handler: any CommandHandling,
         audioSource: (any AudioSource)? = nil) {
        self.settings = settings
        self.speech = speech
        self.handler = handler
        microphone = audioSource ?? MicrophoneCapture()
        flow = ConversationFlow(matcher: settings.makeWakeMatcher())
    }

    func toggle() {
        isRunning ? stop() : start()
    }

    func start() {
        guard listenTask == nil else { return }
        listenTask = Task { await run() }
    }

    func stop() {
        listenTask?.cancel()
        listenTask = nil
        teardown()
        status = .off
    }

    /// Stops the current reply (menu action); the assistant keeps listening.
    func interrupt() {
        resolveConfirmation(.rejected)
        turnTask?.cancel()
        speech.stop()
    }

    /// Answers a pending confirmation from the menu instead of by voice.
    func resolveConfirmation(_ answer: ConfirmationParser.Answer) {
        guard let continuation = confirmationContinuation else { return }
        confirmationContinuation = nil
        continuation.resume(returning: answer)
    }

    /// Speaks something the user did not just ask for (a timer going off), after any reply in progress.
    func announce(_ text: String) async {
        await turnTask?.value
        isAudioSuspended = true
        segmenter.reset()
        status = .speaking
        do {
            try await speech.speak(text)
        } catch {
            Log.audio.error("Announcement failed: \(error.localizedDescription, privacy: .public)")
        }
        await vad?.reset()
        segmenter.reset()
        isAudioSuspended = false
        status = isRunning ? (flow.isAwaitingSpeech ? .awake : .listening) : .off
    }

    // MARK: - Listening loop

    private func run() async {
        guard await microphone.requestPermission() else {
            fail("Mikrofon izni yok. Sistem Ayarları > Gizlilik ve Güvenlik > Mikrofon bölümünden izin ver.")
            listenTask = nil
            return
        }
        do {
            let vad = try await loadModels()
            flow = ConversationFlow(matcher: settings.makeWakeMatcher())
            segmenter.reset()
            startSegmentConsumer()
            startTicker()
            let stream = try microphone.start()
            status = .listening
            Log.wake.info("Listening for wake phrase '\(self.settings.wakePhrase, privacy: .public)'")
            for await samples in stream {
                if Task.isCancelled { break }
                if isAudioSuspended { continue }
                for frame in try await vad.process(samples) { handle(frame) }
            }
        } catch is CancellationError {
            // stop() already cleaned up
        } catch {
            fail(error.localizedDescription)
        }
        if listenTask != nil, !Task.isCancelled {
            teardown()
            listenTask = nil
        }
    }

    private func loadModels() async throws -> VoiceActivityMonitor {
        status = .loading("Ses algılama hazırlanıyor…")
        let vad: VoiceActivityMonitor
        if let existing = self.vad {
            vad = existing
            await vad.reset()
        } else {
            vad = try await VoiceActivityMonitor()
            self.vad = vad
        }

        if recognizer?.engine != settings.recognizer {
            status = .loading("Konuşma tanıma modeli yükleniyor…")
            let recognizer = RecognizerFactory.make(settings.recognizer)
            try await recognizer.prepare()
            self.recognizer = recognizer
        }

        status = .loading("Ses hazırlanıyor…")
        speech.speed = settings.speechSpeed
        try await speech.setVoice(settings.voice)
        try await speech.prepare()
        return vad
    }

    private func handle(_ frame: VoiceActivityFrame) {
        let wasInSpeech = segmenter.isInSpeech
        let segments = segmenter.process(frame.samples, probability: frame.probability)
        if !wasInSpeech, segmenter.isInSpeech { flow.speechStarted(at: .now) }
        segments.forEach { segmentQueue?.yield($0) }
    }

    private func startSegmentConsumer() {
        let (stream, continuation) = AsyncStream<SpeechSegmenter.Segment>.makeStream(bufferingPolicy: .bufferingNewest(4))
        segmentQueue = continuation
        segmentTask = Task {
            for await segment in stream {
                await process(segment)
            }
        }
    }

    private func process(_ segment: SpeechSegmenter.Segment) async {
        guard let recognizer, !isAudioSuspended else { return }
        do {
            if pendingConfirmation != nil {
                let answer = try await recognizer.transcribe(segment.samples)
                lastHeard = answer
                resolveConfirmation(ConfirmationParser.parse(answer))
                return
            }
            let isWakeCheck = flow.phase == .listeningForWake
            if !isWakeCheck { status = .transcribing }
            guard let transcript = try await transcribe(segment.samples, with: recognizer, wakeCheckOnly: isWakeCheck),
                  !isAudioSuspended
            else { return }
            Log.wake.debug("Heard: \(transcript, privacy: .private)")
            let action = flow.heard(transcript, at: .now)
            if action != .none { lastHeard = transcript }
            perform(action)
            if !isWakeCheck, action == .none { status = .awake }
        } catch {
            Log.speech.error("Transcription failed: \(error.localizedDescription, privacy: .public)")
            if flow.phase != .listeningForWake { status = .awake }
        }
    }

    /// While waiting for the wake phrase only the opening seconds are transcribed; the full utterance
    /// is transcribed only if the phrase is there. Keeps background chatter cheap.
    private func transcribe(_ samples: [Float], with recognizer: any SpeechRecognizer, wakeCheckOnly: Bool) async throws -> String? {
        let probeLength = Int(Self.wakeProbeSeconds * StreamingResampler.targetSampleRate)
        guard wakeCheckOnly, samples.count > probeLength else {
            return try await recognizer.transcribe(samples)
        }
        let probe = try await recognizer.transcribe(Array(samples.prefix(probeLength)))
        guard flow.matcher.match(probe) != nil else { return nil }
        return try await recognizer.transcribe(samples)
    }

    private func startTicker() {
        tickTask = Task {
            while !Task.isCancelled {
                try? await Task.sleep(for: Self.tickInterval)
                perform(flow.tick(at: .now))
            }
        }
    }

    // MARK: - Turns

    private func perform(_ action: ConversationFlow.Action) {
        switch action {
        case .none:
            break
        case .acknowledgeWake:
            Earcon.wake.play()
            status = .awake
        case let .runCommand(command):
            turnTask = Task { await runTurn(command) }
        case let .returnToIdle(timedOut):
            if timedOut { Earcon.cancelled.play() }
            handler.endConversation()
            status = .listening
        }
    }

    private func runTurn(_ command: String) async {
        isAudioSuspended = true
        segmenter.reset()
        status = .thinking
        lastReply = ""
        flow.responseStarted()
        do {
            try await speech.speak(streaming: replyFragments(for: command))
        } catch is CancellationError {
            speech.stop()
        } catch {
            Log.brain.error("Turn failed: \(error.localizedDescription, privacy: .public)")
            Earcon.failed.play()
        }
        await vad?.reset()
        segmenter.reset()
        isAudioSuspended = false
        flow.responseFinished(at: .now, allowFollowUp: settings.followUpEnabled)
        if !flow.isAwaitingSpeech { handler.endConversation() }
        status = flow.isAwaitingSpeech ? .awake : .listening
    }

    /// Forwards the handler's reply while mirroring it into the UI.
    private func replyFragments(for command: String) -> AsyncThrowingStream<String, any Error> {
        let source = handler.respond(to: command)
        return AsyncThrowingStream { continuation in
            let forwarding = Task { @MainActor in
                do {
                    for try await fragment in source {
                        lastReply = (lastReply ?? "") + fragment
                        status = .speaking
                        continuation.yield(fragment)
                    }
                    continuation.finish()
                } catch {
                    continuation.finish(throwing: error)
                }
            }
            continuation.onTermination = { _ in forwarding.cancel() }
        }
    }

    // MARK: - Confirmation

    private func waitForConfirmationAnswer() async -> ConfirmationParser.Answer {
        let timeout = Task { [weak self] in
            try? await Task.sleep(for: Self.confirmationTimeout)
            guard !Task.isCancelled, let self else { return }
            // Someone mid-sentence gets a little longer before the question lapses.
            if segmenter.isInSpeech { try? await Task.sleep(for: Self.confirmationGrace) }
            guard !Task.isCancelled else { return }
            resolveConfirmation(.unclear)
        }
        defer { timeout.cancel() }
        return await withCheckedContinuation { confirmationContinuation = $0 }
    }

    // MARK: - Lifecycle

    private func teardown() {
        resolveConfirmation(.rejected)
        tickTask?.cancel()
        segmentTask?.cancel()
        turnTask?.cancel()
        segmentQueue?.finish()
        tickTask = nil
        segmentTask = nil
        turnTask = nil
        segmentQueue = nil
        microphone.stop()
        speech.stop()
        segmenter.reset()
        flow.reset()
        isAudioSuspended = false
        handler.endConversation()
    }

    private func fail(_ message: String) {
        Log.wake.error("Assistant stopped: \(message, privacy: .public)")
        status = .failed(message)
    }
}

extension AssistantController: ConfirmationProviding {
    /// Speaks the question, then listens (no wake phrase needed) for a yes/no or a menu click.
    func confirm(_ question: String) async -> ConfirmationParser.Answer {
        lastReply = question
        status = .speaking
        do {
            try await speech.speak(question)
        } catch {
            Log.audio.error("Could not ask for confirmation: \(error.localizedDescription, privacy: .public)")
            return .unclear
        }
        guard !Task.isCancelled else { return .rejected }
        await vad?.reset()
        segmenter.reset()
        pendingConfirmation = question
        status = .confirming
        isAudioSuspended = false
        let answer = await waitForConfirmationAnswer()
        isAudioSuspended = true
        segmenter.reset()
        pendingConfirmation = nil
        lastReply = ""
        status = .thinking
        Log.tools.info("Confirmation answer: \(String(describing: answer), privacy: .public)")
        return answer
    }
}
