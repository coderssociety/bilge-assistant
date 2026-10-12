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
    }

    private static let script: [Line] = [
        Line(pauseBefore: 1.5, text: "Bugün hava çok güzel, dışarı çıkalım.", expectsReply: false),
        Line(pauseBefore: 2.0, text: "Asistan, saat kaç?", expectsReply: true),
        Line(pauseBefore: 9.0, text: "Asistan.", expectsReply: false),
        Line(pauseBefore: 1.0, text: "Pil durumu nedir?", expectsReply: true),
        Line(pauseBefore: 7.0, text: "Asistan, yüz yirmi beşin yüzde on sekizi kaç eder?", expectsReply: true),
        Line(pauseBefore: 7.0, text: "Teşekkür ederim.", expectsReply: true),
    ]

    static func run() async -> Int32 {
        setvbuf(stdout, nil, _IOLBF, 0)
        do {
            print("Senaryo sesi üretiliyor…")
            let (audio, endTimes) = try await synthesizeScript()
            let defaults = UserDefaults(suiteName: "com.vrnsoft.asistan.bench")!
            defaults.removePersistentDomain(forName: "com.vrnsoft.asistan.bench")
            let settings = AssistantSettings(defaults: defaults)
            let speech = SpeechOutput(voice: .f1)
            speech.isMuted = true
            let tools = ToolRegistry(catalog: AppCatalog(), timers: TimerService { _ in }).makeTools()
            let source = ScriptedAudioSource(samples: audio)
            let brain = AssistantBrain(tools: tools)
            brain.prewarm()
            let assistant = AssistantController(settings: settings, speech: speech, handler: brain, audioSource: source)

            assistant.start()
            while assistant.status != .listening {
                if case let .failed(message) = assistant.status { throw BenchError.failed(message) }
                try await Task.sleep(for: pollInterval)
            }
            let events = try await observe(assistant, duration: Double(audio.count) / StreamingResampler.targetSampleRate)
            assistant.stop()
            report(events: events, endTimes: endTimes)
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
        for (end, line) in endTimes {
            let next = replyStarts.first { $0 > end }
            let window = endTimes.first { $0.0 > end }?.0 ?? .infinity
            let replied = next.map { $0 < window } ?? false
            let verdict = replied == line.expectsReply ? "✓" : "✗"
            let latency = replied ? String(format: "%.2fs", next! - end) : "yanıt yok"
            print("\(verdict) \"\(line.text)\" → \(latency)")
        }
    }

    private static func synthesizeScript() async throws -> ([Float], [(Double, Line)]) {
        let manager = try await Supertonic3Manager.downloadAndCreate()
        let style = try await Supertonic3ResourceDownloader.loadVoiceStyle(.m1)
        let converter = AudioConverter()
        let rate = StreamingResampler.targetSampleRate
        var audio: [Float] = []
        var endTimes: [(Double, Line)] = []
        for line in script {
            audio += [Float](repeating: 0, count: Int(line.pauseBefore * rate))
            let spoken = TurkishSpeechNormalizer.normalize(line.text)
            let result = try await manager.synthesize(text: spoken, language: SpeechOutput.language, style: style)
            audio += try converter.resample(result.samples, from: SpeechOutput.sampleRate)
            endTimes.append((Double(audio.count) / rate, line))
        }
        audio += [Float](repeating: 0, count: Int(tailSilence * rate))
        return (audio, endTimes)
    }
}
