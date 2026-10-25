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
        /// A meeting is being recorded and transcribed.
        case recording
        case failed(String)

        /// Taking a command, answering or asking; not waiting for the wake phrase.
        var holdsAttention: Bool {
            switch self {
            case .awake, .transcribing, .thinking, .speaking, .confirming: true
            case .off, .loading, .listening, .recording, .failed: false
            }
        }
    }

    private static let wakeProbeSeconds = 2.5
    private static let tickInterval = Duration.milliseconds(250)
    private static let confirmationTimeout = Duration.seconds(8)
    private static let confirmationGrace = Duration.seconds(5)

    private(set) var status: Status = .off {
        didSet {
            if status.holdsAttention != oldValue.holdsAttention { onAttentionChange?(status.holdsAttention) }
        }
    }
    /// Told when Bilge starts and stops listening to a command or speaking, so playback can make way.
    @ObservationIgnored var onAttentionChange: ((Bool) -> Void)?
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
    private let whisper: WhisperProvider
    private let recorder: MeetingRecorder
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
    /// The shortcut was pressed while listening was off or still starting.
    private var wakeWhenListening = false
    /// The language the last work input was recognized in, for a session that detects languages.
    private var heardLanguage: String?

    var bargeInDiagnostics: [String] { bargeIn?.diagnostics ?? [] }
    /// Everything the main pipeline transcribed, including speech it ignored (for diagnostics).
    private(set) var recentTranscripts: [String] = []
    private static let maxRecentTranscripts = 40

    private var isBargeInActive: Bool { status == .speaking && bargeIn != nil }
    /// Set by the app; benchmarks run without it.
    var speakerGate: SpeakerGate?

    init(settings: AssistantSettings, speech: SpeechOutput, handler: any CommandHandling,
         audioSource: (any AudioSource)? = nil, whisper: WhisperProvider? = nil, recorder: MeetingRecorder = MeetingRecorder()) {
        self.settings = settings
        self.speech = speech
        self.handler = handler
        self.whisper = whisper ?? WhisperProvider(language: settings.language)
        self.recorder = recorder
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
        wakeWhenListening = false
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

    /// The listening shortcut: like saying the wake phrase; while the assistant answers, like "Bilge, dur". With
    /// listening off it is switched on, and the assistant listens once it has started.
    func shortcutPressed() {
        guard pendingConfirmation == nil else { return }
        switch status {
        case .speaking, .thinking:
            stoppedByUser = true
            interrupt()
        case .listening, .awake, .transcribing:
            let action = flow.shortcutPressed(at: .now)
            if case .returnToIdle = action { Earcon.cancelled.play() }
            perform(action)
        case .recording:
            // Only the stop phrase is acted on while a meeting is recorded.
            break
        case .loading:
            // Without a listening task this is the first-run setup preparing models; it isn't listening yet.
            if isRunning { wakeWhenListening = true }
        case .off, .failed:
            wakeWhenListening = true
            start()
        case .confirming:
            break
        }
    }

    /// The status line; without the wake word, the idle state names the shortcut instead.
    var statusTitle: String {
        guard status == .listening, !settings.listensForWakeWord, let shortcut = settings.listeningShortcut else {
            return status.title
        }
        return String(localized: "Kısayolu bekliyor (\(shortcut.display))")
    }

    /// Ends the meeting recording as if the stop phrase was said (menu action).
    func finishRecording() {
        guard recorder.isRecording, status == .recording else { return }
        startStopRecordingTurn(MeetingCommand.stopPhrase(language: settings.language))
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
        // The shortcut stops an announcement; that must not cut the next reply's follow-up window.
        stoppedByUser = false
        status = isRunning ? restingStatus : .off
    }

    // MARK: - Listening loop

    private func run() async {
        guard await microphone.requestPermission() else {
            fail(String(localized: "Mikrofon izni yok. Sistem Ayarları > Gizlilik ve Güvenlik > Mikrofon bölümünden izin ver."))
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
            if wakeWhenListening {
                wakeWhenListening = false
                perform(flow.shortcutPressed(at: .now))
            }
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
        status = .loading(String(localized: "Ses algılama hazırlanıyor…"))
        let vad: VoiceActivityMonitor
        if let existing = self.vad {
            vad = existing
            await vad.reset()
        } else {
            vad = try await VoiceActivityMonitor()
            self.vad = vad
        }

        if recognizer?.engine != settings.recognizer {
            status = .loading(String(localized: "Konuşma tanıma modeli yükleniyor…"))
            whisper.isListeningEngine = settings.recognizer == .whisper
            if settings.recognizer == .whisper {
                recognizer = try await whisper.prepared()
            } else {
                let recognizer = RecognizerFactory.make(settings.recognizer, language: settings.language)
                try await recognizer.prepare()
                self.recognizer = recognizer
                if !self.recorder.isRecording { whisper.releaseUnlessListening() }
            }
        }

        status = .loading(String(localized: "Ses hazırlanıyor…"))
        speech.speed = settings.speechSpeed
        try await speech.setVoice(settings.voice)
        try await speech.prepare()
        await loadBargeIn()
        return vad
    }

    /// Optional: if echo cancellation cannot load, the assistant still works, just without barge-in.
    private func loadBargeIn() async {
        bargeIn = nil
        // Cutting in is done by saying the wake phrase; without it, the shortcut stops a reply instead.
        guard settings.bargeInEnabled, settings.listensForWakeWord, let recognizer else { return }
        status = .loading(String(localized: "Yankı iptali hazırlanıyor…"))
        do {
            bargeIn = try await BargeInListener(
                timeline: speech.playbackTimeline, recognizer: recognizer,
                detector: BargeInDetector(matcher: settings.makeWakeMatcher(), language: settings.language))
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
        if wasInSpeech, !segmenter.isInSpeech { flow.speechEnded(at: .now) }
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
                resolveConfirmation(ConfirmationParser.parse(answer, strict: confirmationIsStrict, language: settings.language))
                return
            }
            if recorder.isRecording {
                await record(segment.samples)
                return
            }
            let isWakeCheck = flow.phase == .listeningForWake
            if isWakeCheck, !settings.listensForWakeWord { return }
            if !isWakeCheck { status = .transcribing }
            let languages = isWakeCheck ? [] : flow.activeWorkSession?.languages ?? []
            heardLanguage = nil
            let heard: String?
            if languages.isEmpty {
                heard = try await transcribe(segment.samples, with: recognizer, wakeCheckOnly: isWakeCheck)
            } else {
                heard = try await transcribe(segment.samples, detectingAmong: languages, fallback: recognizer)
            }
            guard let transcript = heard, !isAudioSuspended else { return }
            Log.wake.debug("Heard: \(transcript, privacy: .private)")
            // Interpreting is a conversation with someone else, whose voice must be heard too.
            if languages.isEmpty, needsSpeakerCheck(transcript, isWakeCheck: isWakeCheck), await !speakerAllows(segment.samples) {
                recentTranscripts = Array((recentTranscripts + ["başka bir ses (yok sayıldı): “\(transcript)”"]).suffix(Self.maxRecentTranscripts))
                if !isWakeCheck { status = restingStatus }
                return
            }
            recentTranscripts = Array((recentTranscripts + ["\(isWakeCheck ? "uyandırma" : "komut"): “\(transcript)”"]).suffix(Self.maxRecentTranscripts))
            let action = flow.heard(transcript, at: .now)
            if action != .none { lastHeard = transcript }
            perform(action)
            // The shortcut may have closed the window while this was being transcribed.
            if !isWakeCheck, action == .none { status = restingStatus }
        } catch {
            Log.speech.error("Transcription failed: \(error.localizedDescription, privacy: .public)")
            if flow.phase != .listeningForWake { status = restingStatus }
        }
    }

    /// Whisper tells the session's languages apart; Apple dictation cannot, so its sessions use the shared Whisper,
    /// and without one the speech is taken in the assistant's language.
    private func transcribe(_ samples: [Float], detectingAmong languages: [String],
                            fallback: any SpeechRecognizer) async throws -> String {
        let detecting = recognizer?.engine == .whisper ? recognizer : whisper.loaded
        if let detecting, let detected = try await detecting.transcribe(samples, detectingAmong: languages) {
            heardLanguage = detected.language
            return detected.text
        }
        return try await fallback.transcribe(samples)
    }

    /// While a meeting is recorded everything heard is transcribed by Whisper and kept; only the stop phrase is acted
    /// on, whoever says it.
    private func record(_ samples: [Float]) async {
        guard let transcriber = recognizer?.engine == .whisper ? recognizer : whisper.loaded else { return }
        let duration = Double(samples.count) / StreamingResampler.targetSampleRate
        do {
            let text = try await transcriber.transcribe(samples)
            guard !text.isEmpty, recorder.isRecording, !isAudioSuspended else { return }
            recentTranscripts = Array((recentTranscripts + ["kayıt: “\(text)”"]).suffix(Self.maxRecentTranscripts))
            lastHeard = text
            let command = flow.matcher.match(text)?.command ?? text
            if MeetingCommand.parse(command, language: settings.language) == .stopRecording {
                startStopRecordingTurn(command)
                return
            }
            recorder.append(text, duration: duration)
        } catch {
            Log.speech.error("Recording transcription failed: \(error.localizedDescription, privacy: .public)")
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
            startTurn(command)
        case let .runWorkInput(input):
            let language = heardLanguage
            turnTask = Task { await runTurn(input, isWorkInput: true, heard: language) }
        case let .returnToIdle(timedOut):
            if timedOut { Earcon.cancelled.play() }
            handler.endConversation()
            status = restingStatus
        }
    }

    private func startTurn(_ command: String) {
        handler.conversationWillStart()
        turnTask = Task { await runTurn(command) }
    }

    /// Speech queued behind the stop phrase must not start the turn a second time.
    private func startStopRecordingTurn(_ command: String) {
        isAudioSuspended = true
        startTurn(command)
    }

    private var restingStatus: Status {
        if recorder.isRecording { return .recording }
        return flow.isAwaitingSpeech ? .awake : .listening
    }

    private func runTurn(_ command: String, isWorkInput: Bool = false, heard: String? = nil) async {
        isAudioSuspended = true
        segmenter.reset()
        await bargeIn?.reset()
        status = .thinking
        let replyLanguage = handler.replyLanguageCode(for: command, isWorkInput: isWorkInput, heard: heard)
        // "TR → EN: …" while interpreting.
        if isWorkInput, let heard, let replyLanguage {
            lastReply = InterpreterPair.caption(from: heard, to: replyLanguage)
        } else {
            lastReply = ""
        }
        flow.responseStarted()
        speech.replyLanguageCode = replyLanguage
        defer { speech.replyLanguageCode = nil }
        do {
            try await speech.speak(streaming: replyFragments(for: command, isWorkInput: isWorkInput, heard: heard))
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
        status = restingStatus
        if let command = pendingBargeCommand {
            pendingBargeCommand = nil
            perform(flow.heard(command, at: .now))
        }
    }

    /// Forwards the handler's reply while mirroring it into the UI.
    private func replyFragments(for command: String, isWorkInput: Bool, heard: String?) -> AsyncThrowingStream<String, any Error> {
        let source = isWorkInput ? handler.respond(toWorkInput: command, language: heard) : handler.respond(to: command)
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
        wakeWhenListening = false
        Log.wake.error("Assistant stopped: \(message, privacy: .public)")
        status = .failed(message)
    }
}

extension AssistantController: ConfirmationProviding {
    /// Speaks the question, then listens (no wake phrase needed) for a yes/no or a menu click.
    func confirm(_ question: String, strict: Bool) async -> ConfirmationParser.Answer {
        lastReply = question
        status = .speaking
        stoppedByUser = false
        do {
            try await speech.speak(question)
        } catch {
            Log.audio.error("Could not ask for confirmation: \(error.localizedDescription, privacy: .public)")
            return .unclear
        }
        guard !Task.isCancelled else { return .rejected }
        // A "no" that started while the question was still playing is decided only now.
        await settleBargeIn()
        // "No" said before the question ended cuts it off; it is the answer. An early yes is not taken:
        // agreeing by mistake costs more than asking again.
        if stoppedByUser, let heard = lastHeard,
           ConfirmationParser.parse(heard, strict: strict, language: settings.language) == .rejected {
            stoppedByUser = false
            lastReply = ""
            status = .thinking
            Log.tools.info("Confirmation answered during the question: rejected")
            return .rejected
        }
        // Any other cut-in during the question is not about the reply that follows.
        stoppedByUser = false
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
