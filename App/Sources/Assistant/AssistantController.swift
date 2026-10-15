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
    private var confirmationIsStrict = false
    /// Latest speech probability (0...1) for level meters; updated about four times a second.
    private(set) var inputLevel: Float = 0
    /// Increments each time the user cuts the assistant off mid-reply.
    private(set) var interruptionCount = 0
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
    private var bargeIn: BargeInListener?
    /// A request the user made by cutting in; it runs once the interrupted reply has wound down.
    private var pendingBargeCommand: String?
    /// "Bilge, dur" (stop) means silence: no follow-up window, or the rest of the sentence gets answered.
    private var stoppedByUser = false

    var bargeInDiagnostics: [String] { bargeIn?.diagnostics ?? [] }
    /// Everything the main pipeline transcribed, including speech it ignored (for diagnostics).
    private(set) var recentTranscripts: [String] = []
    private static let maxRecentTranscripts = 40

    private var isBargeInActive: Bool { status == .speaking && bargeIn != nil }
    /// Set by the app; benchmarks run without it.
    var speakerGate: SpeakerGate?

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
        inputLevel = 0
        status = .off
    }

    /// Applies changed settings (wake phrase, recognizer, voice) by restarting if listening.
    func restartIfRunning() {
        guard isRunning else { return }
        stop()
        start()
    }

    /// Downloads and loads every model without opening the microphone (first-run setup).
    func prepareModels() async throws {
        guard !isRunning else { return }
        defer { if !isRunning { status = .off } }
        _ = try await loadModels()
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
        await bargeIn?.reset()
        lastReply = text
        status = .speaking
        do {
            try await speech.speak(text)
        } catch {
            Log.audio.error("Announcement failed: \(error.localizedDescription, privacy: .public)")
        }
        await bargeIn?.reset()
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
            for await chunk in stream {
                if Task.isCancelled { break }
                if isAudioSuspended {
                    if isBargeInActive { await listenForBargeIn(chunk) }
                    continue
                }
                for frame in try await vad.process(chunk.samples) { handle(frame) }
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
        await loadBargeIn()
        return vad
    }

    /// Optional: if echo cancellation cannot load, the assistant still works, just without barge-in.
    private func loadBargeIn() async {
        bargeIn = nil
        guard settings.bargeInEnabled, let recognizer else { return }
        status = .loading("Yankı iptali hazırlanıyor…")
        do {
            bargeIn = try await BargeInListener(
                timeline: speech.playbackTimeline, recognizer: recognizer,
                detector: BargeInDetector(matcher: settings.makeWakeMatcher()))
        } catch {
            Log.audio.error("Barge-in disabled: \(error.localizedDescription, privacy: .public)")
        }
    }

    private func listenForBargeIn(_ chunk: AudioChunk) async {
        await bargeIn?.listen(chunk, replySoFar: lastReply ?? "") { [weak self] decision, heard in
            self?.handleBargeIn(decision, heard: heard)
        }
    }

    /// Evaluates speech still pending when the reply ends, then clears barge-in state.
    private func settleBargeIn() async {
        guard let bargeIn else { return }
        if let late = await bargeIn.finish(replySoFar: lastReply ?? "") {
            handleBargeIn(late.decision, heard: late.heard)
        }
        await bargeIn.reset()
    }

    private func handleBargeIn(_ decision: BargeInDetector.Decision, heard: String) {
        guard status == .speaking else { return }
        lastHeard = heard
        switch decision {
        case let .command(command): pendingBargeCommand = command
        case .stop: stoppedByUser = true
        case .none: return
        }
        Log.wake.info("User cut in: \(String(describing: decision), privacy: .public)")
        interruptionCount += 1
        interrupt()
    }

    private func handle(_ frame: VoiceActivityFrame) {
        inputLevel = frame.probability
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
                // A "yes" from the TV must not confirm a message being sent.
                guard await speakerAllows(segment.samples) else { return }
                let answer = try await recognizer.transcribe(segment.samples)
                lastHeard = answer
                resolveConfirmation(ConfirmationParser.parse(answer, strict: confirmationIsStrict))
                return
            }
            let isWakeCheck = flow.phase == .listeningForWake
            if !isWakeCheck { status = .transcribing }
            guard let transcript = try await transcribe(segment.samples, with: recognizer, wakeCheckOnly: isWakeCheck),
                  !isAudioSuspended
            else { return }
            Log.wake.debug("Heard: \(transcript, privacy: .private)")
            if needsSpeakerCheck(transcript, isWakeCheck: isWakeCheck), await !speakerAllows(segment.samples) {
                recentTranscripts = Array((recentTranscripts + ["başka bir ses (yok sayıldı): “\(transcript)”"]).suffix(Self.maxRecentTranscripts))
                if !isWakeCheck { status = .awake }
                return
            }
            recentTranscripts = Array((recentTranscripts + ["\(isWakeCheck ? "uyandırma" : "komut"): “\(transcript)”"]).suffix(Self.maxRecentTranscripts))
            let action = flow.heard(transcript, at: .now)
            if action != .none { lastHeard = transcript }
            perform(action)
            if !isWakeCheck, action == .none { status = .awake }
        } catch {
            Log.speech.error("Transcription failed: \(error.localizedDescription, privacy: .public)")
            if flow.phase != .listeningForWake { status = .awake }
        }
    }

    /// Commands and work input are checked; a bare wake phrase is too short to judge, so the command
    /// after it is checked instead.
    private func needsSpeakerCheck(_ transcript: String, isWakeCheck: Bool) -> Bool {
        guard speakerGate?.isActive == true else { return false }
        guard isWakeCheck else { return true }
        guard let match = flow.matcher.match(transcript) else { return false }
        return !match.command.isEmpty
    }

    private func speakerAllows(_ samples: [Float]) async -> Bool {
        guard let speakerGate, speakerGate.isActive else { return true }
        return await speakerGate.check(samples) != .rejected
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
            handler.conversationWillStart()
            status = .awake
        case let .runCommand(command):
            handler.conversationWillStart()
            turnTask = Task { await runTurn(command) }
        case let .runWorkInput(input):
            turnTask = Task { await runTurn(input, isWorkInput: true) }
        case let .returnToIdle(timedOut):
            if timedOut { Earcon.cancelled.play() }
            handler.endConversation()
            status = .listening
        }
    }

    private func runTurn(_ command: String, isWorkInput: Bool = false) async {
        isAudioSuspended = true
        segmenter.reset()
        await bargeIn?.reset()
        status = .thinking
        lastReply = ""
        flow.responseStarted()
        do {
            try await speech.speak(streaming: replyFragments(for: command, isWorkInput: isWorkInput))
        } catch is CancellationError {
            speech.stop()
        } catch {
            Log.brain.error("Turn failed: \(error.localizedDescription, privacy: .public)")
            Earcon.failed.play()
        }
        await settleBargeIn()
        await vad?.reset()
        segmenter.reset()
        isAudioSuspended = false
        let allowFollowUp = pendingBargeCommand != nil || (!stoppedByUser && settings.followUpEnabled)
        let session = stoppedByUser ? nil : handler.workSession
        stoppedByUser = false
        flow.responseFinished(at: .now, allowFollowUp: allowFollowUp, session: session)
        if !flow.isAwaitingSpeech { handler.endConversation() }
        status = flow.isAwaitingSpeech ? .awake : .listening
        if let command = pendingBargeCommand {
            pendingBargeCommand = nil
            perform(flow.heard(command, at: .now))
        }
    }

    /// Forwards the handler's reply while mirroring it into the UI.
    private func replyFragments(for command: String, isWorkInput: Bool) -> AsyncThrowingStream<String, any Error> {
        let source = isWorkInput ? handler.respond(toWorkInput: command) : handler.respond(to: command)
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
    func confirm(_ question: String, strict: Bool) async -> ConfirmationParser.Answer {
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
        confirmationIsStrict = strict
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
