import AsistanCore
import FluidAudio
import Foundation

/// Calibrates speaker verification on synthetic voices: `Asistan --bench-speaker`. Each enrolled voice
/// reads five commands; its eight other commands should pass and every other voice's should not.
/// TTS voices share a vocoder, so they are closer to one another than people are: a cautious test.
@MainActor
enum SpeakerBenchmark {
    static let flag = "--bench-speaker"

    private static let enrollment = [
        "Bilge, saat kaç?", "Bilge, yarın hava nasıl olacak?", "Bilge, müziği biraz kıs.",
        "Bilge, bugün takvimimde ne var?", "Bilge, Ahmet'e geç kalacağımı yaz.",
    ]
    private static let trials = [
        "Bilge, sesi yüzde otuz yap.", "Bilge, dolar kaç lira?", "Bilge, bana bir fıkra anlat.", "Bilge, son indirdiğim dosyayı aç.",
        "Bilge, beş dakika sonra hatırlat.", "Bilge, pil durumu nedir?", "Bilge, Safari'yi kapat.", "Bilge, günün özeti.",
    ]
    private static let enrolledVoices: [Supertonic3Voice] = [.f1, .m1]

    static func run() async -> Int32 {
        setvbuf(stdout, nil, _IOLBF, 0)
        do {
            let manager = try await Supertonic3Manager.downloadAndCreate()
            let converter = AudioConverter()
            let verifier = SpeakerVerifier()
            var embeddings: [Supertonic3Voice: (enroll: [[Float]], trial: [[Float]])] = [:]
            for voice in Supertonic3Voice.allCases {
                let style = try await Supertonic3ResourceDownloader.loadVoiceStyle(voice)
                func embed(_ text: String) async throws -> [Float] {
                    let result = try await manager.synthesize(text: TurkishSpeechNormalizer.normalize(text), language: AssistantLanguage.turkish.code, style: style)
                    return try await verifier.embedding(of: try converter.resample(result.samples, from: SpeechOutput.sampleRate))
                }
                var enroll: [[Float]] = []
                for text in enrollment { enroll.append(try await embed(text)) }
                var trial: [[Float]] = []
                for text in trials { trial.append(try await embed(text)) }
                embeddings[voice] = (enroll, trial)
            }
            var genuine: [Float] = []
            var impostor: [Float] = []
            for voice in enrolledVoices {
                guard let voicePrint = VoicePrint(embeddings: embeddings[voice]!.enroll) else { continue }
                let own = embeddings[voice]!.trial.map(voicePrint.score)
                let others = Supertonic3Voice.allCases.filter { $0 != voice }.flatMap { embeddings[$0]!.trial.map(voicePrint.score) }
                genuine += own
                impostor += others
                print(String(format: "%@ tutarlılık %.2f · kendi sesi %.2f–%.2f · diğerleri %.2f–%.2f (en yakın: %@)",
                             voice.rawValue, voicePrint.consistency, own.min()!, own.max()!, others.min()!, others.max()!,
                             closest(to: voicePrint, embeddings: embeddings, excluding: voice)))
            }
            try await checkGate(manager: manager, converter: converter)
            for threshold in stride(from: Float(0.30), through: 0.80, by: 0.05) {
                let falseReject = genuine.filter { $0 < threshold }.count
                let falseAccept = impostor.filter { $0 >= threshold }.count
                print(String(format: "eşik %.2f: kendi sesi reddedilen %d/%d · başkası kabul edilen %d/%d",
                             threshold, falseReject, genuine.count, falseAccept, impostor.count))
            }
            return 0
        } catch {
            print("Hata: \(error)")
            return 1
        }
    }

    /// The gate as the app uses it: enrolled the way the settings sheet does, then fed whole utterances.
    private static func checkGate(manager: Supertonic3Manager, converter: AudioConverter) async throws {
        let defaults = UserDefaults(suiteName: "com.vrnsoft.asistan.bench")!
        defaults.removePersistentDomain(forName: "com.vrnsoft.asistan.bench")
        let settings = AssistantSettings(defaults: defaults)
        settings.speakerCheckEnabled = true
        let gate = SpeakerGate(store: VoiceprintStore(fileURL: nil), settings: settings)
        func audio(_ text: String, _ voice: Supertonic3Voice) async throws -> [Float] {
            let style = try await Supertonic3ResourceDownloader.loadVoiceStyle(voice)
            let result = try await manager.synthesize(text: TurkishSpeechNormalizer.normalize(text), language: AssistantLanguage.turkish.code, style: style)
            return try converter.resample(result.samples, from: SpeechOutput.sampleRate)
        }
        var enrolled: [[Float]] = []
        for prompt in VoiceEnrollment.prompts { enrolled.append(try await gate.verifier.embedding(of: try await audio(prompt, .f1))) }
        try gate.store.save(VoicePrint(embeddings: enrolled)!)
        print(String(format: "kapı: F1 kaydedildi, eşik %.2f", gate.store.stored!.threshold))
        var failures = 0
        for (text, voice, expected) in [
            ("Bilge, sesi yüzde otuz yap.", Supertonic3Voice.f1, SpeakerCheck.Decision.accepted),
            ("Bilge, bana bir fıkra anlat.", .f1, .accepted),
            ("Bilge, sesi yüzde otuz yap.", .m1, .rejected),
            ("Bilge, bana bir fıkra anlat.", .f3, .rejected),
            ("Evet, gönder.", .m2, .rejected),
            ("Bilge.", .m1, .tooShort),
        ] {
            var samples = try await audio(text, voice)
            if expected == .tooShort { samples = Array(samples.prefix(Int(0.5 * StreamingResampler.targetSampleRate))) }
            let decision = await gate.check(samples)
            if decision != expected { failures += 1 }
            print("kapı: \(decision == expected ? "✓" : "✗") \(voice.rawValue) “\(text)” → \(decision)")
        }
        print("kapı: \(failures == 0 ? "TAMAM" : "\(failures) HATA")")
    }

    private static func closest(to voicePrint: VoicePrint, embeddings: [Supertonic3Voice: (enroll: [[Float]], trial: [[Float]])],
                                excluding voice: Supertonic3Voice) -> String {
        let best = Supertonic3Voice.allCases.filter { $0 != voice }.max { a, b in
            (embeddings[a]!.trial.map(voicePrint.score).max() ?? 0) < (embeddings[b]!.trial.map(voicePrint.score).max() ?? 0)
        }
        return best?.rawValue ?? "?"
    }
}
