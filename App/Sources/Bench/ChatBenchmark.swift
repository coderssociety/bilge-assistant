import AsistanCore
import Foundation

/// Knowledge-answer benchmark through the full brain (routing + conversation):
/// `Asistan --bench-chat <questions.tsv> [lmstudio-model-id]`. Each line is "question<TAB>key|key";
/// an answer passes when it contains one of the keys. Without a model id, Apple's model answers.
@MainActor
enum ChatBenchmark {
    static let flag = "--bench-chat"

    static func run(arguments: [String]) async -> Int32 {
        setvbuf(stdout, nil, _IOLBF, 0)
        guard let index = arguments.firstIndex(of: flag), arguments.count > index + 1 else {
            print("Kullanım: Asistan \(flag) <sorular.tsv> [lmstudio-model]")
            return 2
        }
        let cases: [(String, [String])]
        do {
            cases = try String(contentsOf: URL(filePath: arguments[index + 1]), encoding: .utf8)
                .split(separator: "\n")
                .map { $0.split(separator: "\t", maxSplits: 1).map(String.init) }
                .filter { $0.count == 2 }
                .map { ($0[0], $0[1].split(separator: "|").map { TurkishText.lowercased(String($0)) }) }
        } catch {
            print("Sorular okunamadı: \(error.localizedDescription)")
            return 1
        }
        let brain = AssistantBrain(tools: ToolRegistry(catalog: AppCatalog(), timers: TimerService { _ in }).makeTools())
        if arguments.count > index + 2 {
            brain.useLocalModel(arguments[index + 2])
            guard await brain.waitForLocalModel() else {
                print("LM Studio modeli hazırlanamadı: \(arguments[index + 2])")
                return 1
            }
        }
        var passed = 0
        var firstChunkTimes: [Double] = []
        for (question, keys) in cases {
            brain.endConversation()
            let started = Date()
            var answer = ""
            var firstChunk: Double?
            do {
                for try await chunk in brain.respond(to: question) {
                    firstChunk = firstChunk ?? Date.now.timeIntervalSince(started)
                    answer += chunk
                }
            } catch {
                answer = "HATA: \(error)"
            }
            let total = Date.now.timeIntervalSince(started)
            let hit = keys.contains { TurkishText.lowercased(answer).contains($0) }
            passed += hit ? 1 : 0
            firstChunkTimes.append(firstChunk ?? total)
            let timing = String(format: "%.2f/%.2fs", firstChunk ?? -1, total)
            print("\(hit ? "✓" : "✗") [\(timing)] \(question) → \(answer.replacingOccurrences(of: "\n", with: " ").prefix(140))")
        }
        let median = firstChunkTimes.sorted()[firstChunkTimes.count / 2]
        print(String(format: "Doğru: %d/%d · ilk yanıt parçası medyan %.2f sn", passed, cases.count, median))
        return 0
    }
}
