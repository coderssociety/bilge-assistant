import FluidAudio
import Foundation
import Observation

/// Drives the audio lab window: live VAD meter for the microphone and a Turkish TTS playground.
@MainActor
@Observable
final class AudioLabModel {
    struct LogEntry: Identifiable {
        let id = UUID()
        let date: Date
        let message: String
    }

    private static let maxLogEntries = 12

    var isListening = false
    var isSpeechActive = false
    var speechProbability: Float = 0
    var text = "Merhaba! Saat 14:30'da toplantın var; pilin %80 dolu."
    var voice: Supertonic3Voice = .f1
    var speed: Float = 1.05
    var isSpeaking = false
    var statusMessage: String?
    private(set) var log: [LogEntry] = []

    private let microphone = MicrophoneCapture()
    private let speech: SpeechOutput
    private var detector: VoiceActivityDetector?
    private var listenTask: Task<Void, Never>?
    private var speakTask: Task<Void, Never>?

    init(speech: SpeechOutput) {
        self.speech = speech
    }

    func toggleListening() {
        isListening ? stopListening() : startListening()
    }

    func speak() {
        speakTask?.cancel()
        speech.stop()
        let text = text
        speakTask = Task {
            isSpeaking = true
            defer { isSpeaking = false }
            do {
                speech.speed = speed
                try await speech.setVoice(voice)
                let started = Date()
                try await speech.speak(text)
                append("Konuşma bitti (\(Self.seconds(since: started)) sn)")
            } catch is CancellationError {
                append("Konuşma durduruldu")
            } catch {
                report(error)
            }
        }
    }

    func stopSpeaking() {
        speakTask?.cancel()
        speech.stop()
    }

    private func startListening() {
        listenTask = Task {
            guard await MicrophoneCapture.requestPermission() else {
                statusMessage = "Mikrofon izni yok. Sistem Ayarları > Gizlilik ve Güvenlik > Mikrofon."
                return
            }
            do {
                let detector = try await loadDetector()
                let stream = try microphone.start()
                isListening = true
                append("Dinleme başladı")
                for await samples in stream {
                    for update in try await detector.process(samples) { apply(update) }
                }
            } catch {
                report(error)
            }
            stopListening()
        }
    }

    private func stopListening() {
        listenTask?.cancel()
        listenTask = nil
        microphone.stop()
        if isListening { append("Dinleme durdu") }
        isListening = false
        isSpeechActive = false
        speechProbability = 0
    }

    private func loadDetector() async throws -> VoiceActivityDetector {
        if let detector {
            await detector.reset()
            return detector
        }
        statusMessage = "Ses algılama modeli yükleniyor…"
        let loaded = try await VoiceActivityDetector()
        detector = loaded
        statusMessage = nil
        return loaded
    }

    private func apply(_ update: VoiceActivityUpdate) {
        speechProbability = update.probability
        switch update.event {
        case .speechStarted:
            isSpeechActive = true
            append("Konuşma algılandı")
        case .speechEnded:
            isSpeechActive = false
            append("Konuşma bitti")
        case nil:
            break
        }
    }

    private func report(_ error: Error) {
        statusMessage = error.localizedDescription
        append("Hata: \(error.localizedDescription)")
    }

    private func append(_ message: String) {
        log = Array(([LogEntry(date: .now, message: message)] + log).prefix(Self.maxLogEntries))
    }

    private static func seconds(since date: Date) -> String {
        Date.now.timeIntervalSince(date).formatted(.number.precision(.fractionLength(2)))
    }
}
