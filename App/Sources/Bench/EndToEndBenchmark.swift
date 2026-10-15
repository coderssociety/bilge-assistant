import AsistanCore
import FluidAudio
import Foundation

/// Runs the real assistant loop on scripted speech instead of the microphone:
/// `Asistan --bench-e2e`. Only read-only tools are triggered, and speech output is muted.
@MainActor
enum EndToEndBenchmark {
    static let flag = "--bench-e2e"
    private static let tailSilence = 10.0
    private static let pollInterval = Duration.milliseconds(20)

    private struct Line {
        let pauseBefore: Double
        let text: String
        let expectsReply: Bool
        /// Spoken while the assistant is still talking; it must stop speaking promptly.
        var interrupts = false
    }

    private static let maxInterruptLatency = 3.0

    private static let englishScript: [Line] = [
        Line(pauseBefore: 1.5, text: "The weather is lovely today, let's go out.", expectsReply: false),
        Line(pauseBefore: 2.0, text: "Bilge, what time is it?", expectsReply: true),
        Line(pauseBefore: 9.0, text: "Bilge.", expectsReply: false),
        Line(pauseBefore: 1.0, text: "What's my battery level?", expectsReply: true),
        Line(pauseBefore: 7.0, text: "Bilge, what is 18 percent of 125?", expectsReply: true),
        Line(pauseBefore: 7.0, text: "Thank you.", expectsReply: true),
        Line(pauseBefore: 9.0, text: "Bilge, add a dentist appointment tomorrow at ten.", expectsReply: true),
        Line(pauseBefore: 8.0, text: "No.", expectsReply: true),
        Line(pauseBefore: 6.0, text: "Bilge, tell me about the history of London.", expectsReply: true),
        Line(pauseBefore: 5.0, text: "Bilge, stop.", expectsReply: false, interrupts: true),
        Line(pauseBefore: 8.0, text: "Bilge, tell me about New York.", expectsReply: true),
        Line(pauseBefore: 5.0, text: "Bilge, what time is it?", expectsReply: true, interrupts: true),
    ]

    private static let script: [Line] = [
        Line(pauseBefore: 1.5, text: "Bugün hava çok güzel, dışarı çıkalım.", expectsReply: false),
        Line(pauseBefore: 2.0, text: "Bilge, saat kaç?", expectsReply: true),
        Line(pauseBefore: 9.0, text: "Bilge.", expectsReply: false),
        Line(pauseBefore: 1.0, text: "Pil durumu nedir?", expectsReply: true),
        Line(pauseBefore: 7.0, text: "Bilge, yüz yirmi beşin yüzde on sekizi kaç eder?", expectsReply: true),
        Line(pauseBefore: 7.0, text: "Teşekkür ederim.", expectsReply: true),
        Line(pauseBefore: 9.0, text: "Bilge, yarın saat onda diş hekimi randevusu ekle.", expectsReply: true),
        Line(pauseBefore: 8.0, text: "Hayır.", expectsReply: true),
        Line(pauseBefore: 6.0, text: "Bilge, bana İstanbul'un tarihini anlat.", expectsReply: true),
        Line(pauseBefore: 5.0, text: "Bilge, dur.", expectsReply: false, interrupts: true),
        Line(pauseBefore: 8.0, text: "Bilge, bana Ankara'yı anlat.", expectsReply: true),
        Line(pauseBefore: 5.0, text: "Bilge, saat kaç?", expectsReply: true, interrupts: true),
    ]

    /// `--language en` plays an English script; the wake word stays Turkish-pronounced, as a user would say it.
    static func run(arguments: [String]) async -> Int32 {
        setvbuf(stdout, nil, _IOLBF, 0)
        let language = ASRBenchmark.languageArgument(arguments)
        do {
            print("Senaryo sesi üretiliyor…")
            let (audio, endTimes) = try await synthesizeScript(language == .english ? englishScript : script, language: language)
            let defaults = UserDefaults(suiteName: "com.vrnsoft.asistan.bench")!
            defaults.removePersistentDomain(forName: "com.vrnsoft.asistan.bench")
            let settings = AssistantSettings(defaults: defaults)
            let speech = SpeechOutput(voice: .f1, language: language)
            speech.isMuted = true
            let tools = ToolRegistry(catalog: AppCatalog(), timers: TimerService { _ in }, language: language).makeTools()
            // A laptop speaker leaking into its own microphone: 60 ms late, half as loud.
            let source = ScriptedAudioSource(
                samples: audio, echo: .init(timeline: speech.playbackTimeline, delay: 0.06, gain: 0.5))
            let brain = AssistantBrain(tools: tools, language: language)
            brain.prewarm()
            let assistant = AssistantController(settings: settings, speech: speech, handler: brain, audioSource: source)
            brain.confirmer = assistant

            assistant.start()
            while assistant.status != .listening {
                if case let .failed(message) = assistant.status { throw BenchError.failed(message) }
                try await Task.sleep(for: pollInterval)
            }
            let events = try await observe(assistant, duration: Double(audio.count) / StreamingResampler.targetSampleRate)
            let bargeLog = assistant.bargeInDiagnostics
            let transcripts = assistant.recentTranscripts
            assistant.stop()
            report(events: events, endTimes: endTimes)
            print("— Söz kesme dinleyicisinin duydukları —")
            bargeLog.forEach { print("  \($0)") }
            print("— Ana dinleme hattının duydukları —")
            transcripts.forEach { print("  \($0)") }
            return 0
        } catch {
            print("Uçtan uca test başarısız: \(error.localizedDescription)")
            return 1
        }
    }

    private enum BenchError: LocalizedError {
        case failed(String)
        var errorDescription: String? { if case let .failed(message) = self { message } else { nil } }
    }

    private struct Event {
        let time: Double
        let description: String
        let isReplyStart: Bool
    }

    private static func observe(_ assistant: AssistantController, duration: Double) async throws -> [Event] {
        let clock = ContinuousClock()
        let start = clock.now
        var events: [Event] = []
        var lastStatus = assistant.status
        var lastHeard = assistant.lastHeard
        var lastReply = assistant.lastReply
        var lastInterruptions = assistant.interruptionCount
        while true {
            let elapsed = start.duration(to: clock.now)
            let seconds = Double(elapsed.components.seconds) + Double(elapsed.components.attoseconds) / 1e18
            if seconds > duration + 2 { break }
            if assistant.status != lastStatus {
                lastStatus = assistant.status
                events.append(Event(time: seconds, description: "durum: \(lastStatus.title)", isReplyStart: lastStatus == .speaking))
            }
            if assistant.lastHeard != lastHeard, let heard = assistant.lastHeard {
                lastHeard = heard
                events.append(Event(time: seconds, description: "duyulan: \(heard)", isReplyStart: false))
            }
            if assistant.interruptionCount != lastInterruptions {
                lastInterruptions = assistant.interruptionCount
                events.append(Event(time: seconds, description: "kesildi", isReplyStart: false))
            }
            if let reply = assistant.lastReply, !reply.isEmpty, !reply.hasPrefix(lastReply ?? "\u{0}"), lastStatus == .speaking {
                events.append(Event(time: seconds, description: "yeni yanıt", isReplyStart: true))
            }
            if assistant.lastReply != lastReply, let reply = assistant.lastReply, assistant.status != .speaking || reply.count > (lastReply?.count ?? 0) + 40 {
                lastReply = reply
                if !reply.isEmpty { events.append(Event(time: seconds, description: "yanıt: \(reply)", isReplyStart: false)) }
            }
            try await Task.sleep(for: pollInterval)
        }
        return events
    }

    private static func report(events: [Event], endTimes: [(Double, Line)]) {
        for event in events {
            print(String(format: "%6.2fs  %@", event.time, event.description))
        }
        print("— Gecikme (konuşma bitişi → yanıtın başlaması) —")
        let replyStarts = events.filter(\.isReplyStart).map(\.time)
        let statusEvents = events.filter { $0.description.hasPrefix("durum:") }
        let speakingStops = (zip(statusEvents, statusEvents.dropFirst())
            .filter { $0.0.isReplyStart && !$0.1.isReplyStart }
            .map(\.1.time) + events.filter { $0.description == "kesildi" }.map(\.time)).sorted()
        for (index, (end, line)) in endTimes.enumerated() where line.interrupts {
            // Stopping already while the user is still saying "Bilge, dur" counts as instant.
            let start = index > 0 ? endTimes[index - 1].0 + line.pauseBefore : 0
            let stop = speakingStops.first { $0 > start }
            let latency = stop.map { max(0, $0 - end) }
            let passed = latency.map { $0 <= maxInterruptLatency } ?? false
            print("\(passed ? "✓" : "✗") söz kesme \"\(line.text)\" → \(latency.map { String(format: "%.2fs", $0) } ?? "susmadı")")
        }
        for (end, line) in endTimes {
            let next = replyStarts.first { $0 > end }
            let window = endTimes.first { $0.0 > end }?.0 ?? .infinity
            let replied = next.map { $0 < window } ?? false
            let verdict = replied == line.expectsReply ? "✓" : "✗"
            let latency = replied ? String(format: "%.2fs", next! - end) : "yanıt yok"
            print("\(verdict) \"\(line.text)\" → \(latency)")
        }
    }

    private static let silenceLevel: Float = 0.01
    /// Keeps a short margin so word onsets are not clipped.
    private static let keptMargin = 800

    private static func trimmed(_ samples: [Float]) -> [Float] {
        guard let first = samples.firstIndex(where: { abs($0) > silenceLevel }),
              let last = samples.lastIndex(where: { abs($0) > silenceLevel }) else { return samples }
        return Array(samples[max(0, first - keptMargin)...min(samples.count - 1, last + keptMargin)])
    }

    private static func synthesizeScript(_ script: [Line], language: AssistantLanguage) async throws -> ([Float], [(Double, Line)]) {
        let manager = try await Supertonic3Manager.downloadAndCreate()
        let style = try await Supertonic3ResourceDownloader.loadVoiceStyle(.m1)
        let converter = AudioConverter()
        let rate = StreamingResampler.targetSampleRate
        var audio: [Float] = []
        var endTimes: [(Double, Line)] = []
        for line in script {
            audio += [Float](repeating: 0, count: Int(line.pauseBefore * rate))
            var pieces = [(line.text, language)]
            if language == .english, line.text.hasPrefix(AppIdentity.name) {
                let rest = line.text.dropFirst(AppIdentity.name.count).drop { $0 == "," || $0 == "." || $0 == " " }
                pieces = [(AppIdentity.name, .turkish)] + (rest.isEmpty ? [] : [(String(rest), .english)])
            }
            for (text, pieceLanguage) in pieces {
                let spoken = SpokenText.normalize(text, language: pieceLanguage)
                let result = try await manager.synthesize(text: spoken, language: pieceLanguage.code, style: style)
                let samples = try converter.resample(result.samples, from: SpeechOutput.sampleRate)
                // Pieces of one sentence are joined without their own silences, as a person says them in one breath.
                audio += pieces.count > 1 ? trimmed(samples) : samples
            }
            endTimes.append((Double(audio.count) / rate, line))
        }
        audio += [Float](repeating: 0, count: Int(tailSilence * rate))
        return (audio, endTimes)
    }
}
