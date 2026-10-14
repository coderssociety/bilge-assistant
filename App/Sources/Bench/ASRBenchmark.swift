import AsistanCore
import FluidAudio
import Foundation

/// Headless ASR comparison: `Asistan --bench-asr <corpus.txt> <output-dir> [--language en] [--voice-language tr]`.
/// `--voice-language` synthesizes in another language than the recognizer's, e.g. a Turkish "Bilge" heard in English.
/// Utterances are synthesized with Supertonic (clean studio-like audio), so absolute WER is optimistic;
/// the result is for ranking engines, not for promising real-world accuracy.
@MainActor
enum ASRBenchmark {
    static let flag = "--bench-asr"
    private static let voices: [Supertonic3Voice] = [.f1, .m1, .f3, .m4]
    private static let paddingSeconds = 0.3
    private static let noiseAmplitude: Float = 0.003

    struct Sample: Sendable {
        let reference: String
        let voice: String
        let audio: [Float]
    }

    struct EngineReport: Codable {
        let engine: String
        let prepareSeconds: Double
        let wer: Double
        let latencyP50: Double
        let latencyP95: Double
        let failures: [Failure]
    }

    struct Failure: Codable {
        let voice: String
        let reference: String
        let hypothesis: String
    }

    static func run(arguments: [String]) async -> Int32 {
        guard let index = arguments.firstIndex(of: flag), arguments.count > index + 2 else {
            print("Kullanım: Asistan \(flag) <komutlar.txt> <çıktı-klasörü>")
            return 2
        }
        let language = languageArgument(arguments)
        let corpusURL = URL(filePath: arguments[index + 1])
        let outputURL = URL(filePath: arguments[index + 2], directoryHint: .isDirectory)
        do {
            let references = try String(contentsOf: corpusURL, encoding: .utf8)
                .split(whereSeparator: \.isNewline).map(String.init).filter { !$0.isEmpty }
            print("Sentetik ses üretiliyor: \(references.count) komut × \(voices.count) ses")
            let voiceLanguage = arguments.firstIndex(of: "--voice-language").flatMap { index in
                arguments.indices.contains(index + 1) ? AssistantLanguage(rawValue: arguments[index + 1]) : nil
            } ?? language
            let samples = try await synthesize(references, language: voiceLanguage)
            var reports: [EngineReport] = []
            for engine in RecognizerEngine.allCases {
                print("Ölçülüyor: \(engine.displayName)")
                reports.append(try await evaluate(RecognizerFactory.make(engine, language: language), on: samples, language: language))
            }
            try write(reports, to: outputURL)
            return 0
        } catch {
            print("Kıyas başarısız: \(error.localizedDescription)")
            return 1
        }
    }

    /// `--language en`; Turkish when absent.
    static func languageArgument(_ arguments: [String]) -> AssistantLanguage {
        guard let index = arguments.firstIndex(of: "--language"), arguments.count > index + 1 else { return .turkish }
        return AssistantLanguage(rawValue: arguments[index + 1]) ?? .turkish
    }

    private static func synthesize(_ references: [String], language: AssistantLanguage) async throws -> [Sample] {
        let manager = try await Supertonic3Manager.downloadAndCreate()
        let converter = AudioConverter()
        var generator = SystemRandomNumberGenerator()
        var samples: [Sample] = []
        for voice in voices {
            let style = try await Supertonic3ResourceDownloader.loadVoiceStyle(voice)
            for reference in references {
                let spoken = SpokenText.normalize(reference, language: language)
                let result = try await manager.synthesize(text: spoken, language: language.code, style: style)
                let audio16k = try converter.resample(result.samples, from: SpeechOutput.sampleRate)
                samples.append(Sample(reference: reference, voice: voice.rawValue,
                                      audio: padded(audio16k, generator: &generator)))
            }
        }
        return samples
    }

    private static func padded(_ audio: [Float], generator: inout SystemRandomNumberGenerator) -> [Float] {
        let padding = Int(paddingSeconds * StreamingResampler.targetSampleRate)
        let framed = [Float](repeating: 0, count: padding) + audio + [Float](repeating: 0, count: padding)
        return framed.map { $0 + Float.random(in: -noiseAmplitude...noiseAmplitude, using: &generator) }
    }

    private static func evaluate(
        _ recognizer: any SpeechRecognizer, on samples: [Sample], language: AssistantLanguage
    ) async throws -> EngineReport {
        let prepareStart = Date()
        try await recognizer.prepare()
        let prepareSeconds = Date.now.timeIntervalSince(prepareStart)
        _ = try await recognizer.transcribe(samples[0].audio)

        var scores: [WordErrorRate] = []
        var latencies: [Double] = []
        var failures: [Failure] = []
        for sample in samples {
            let started = Date()
            let hypothesis = try await recognizer.transcribe(sample.audio)
            latencies.append(Date.now.timeIntervalSince(started))
            let score = WordErrorRate.compute(reference: sample.reference, hypothesis: hypothesis, language: language)
            scores.append(score)
            if score.errors > 0 {
                failures.append(Failure(voice: sample.voice, reference: sample.reference, hypothesis: hypothesis))
            }
        }
        let sorted = latencies.sorted()
        let report = EngineReport(
            engine: recognizer.engine.rawValue,
            prepareSeconds: prepareSeconds,
            wer: WordErrorRate.aggregate(scores),
            latencyP50: percentile(sorted, 0.5),
            latencyP95: percentile(sorted, 0.95),
            failures: failures)
        print(String(format: "  WER %.1f%%  p50 %.2fs  p95 %.2fs  hatalı %d/%d",
                     report.wer * 100, report.latencyP50, report.latencyP95, failures.count, samples.count))
        return report
    }

    private static func percentile(_ sorted: [Double], _ fraction: Double) -> Double {
        guard !sorted.isEmpty else { return 0 }
        return sorted[min(sorted.count - 1, Int(Double(sorted.count - 1) * fraction))]
    }

    private static func write(_ reports: [EngineReport], to directory: URL) throws {
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes]
        try encoder.encode(reports).write(to: directory.appending(path: "asr-report.json"))
        print("Rapor: \(directory.appending(path: "asr-report.json").path)")
    }
}
