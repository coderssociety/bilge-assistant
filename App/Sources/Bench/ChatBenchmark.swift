import AsistanCore
import Foundation
import Synchronization

/// Knowledge-answer benchmark through the full brain (routing + conversation):
/// `Asistan --bench-chat <questions.tsv> [lmstudio:<id> | vmlx:<publisher/id> | builtin:<catalog id> | mlx:<folder> | folder:<model folder path>]`. Each line is "question<TAB>key|key";
/// an answer passes when it contains one of the keys. Without a model id, Apple's model answers.
/// A catalog model that is not on disk yet is downloaded first, as the app would.
/// `--on-demand` exercises the default lifecycle instead: load on wake, free when the exchange ends.
@MainActor
enum ChatBenchmark {
    static let flag = "--bench-chat"
    static let onDemandFlag = "--on-demand"
    /// With `--on-demand`: all questions form one conversation, ended only after the last one.
    static let sameConversationFlag = "--same-conversation"
    /// Roughly how long a user speaks between the wake phrase and the end of the question.
    private static let simulatedSpeech: Duration = .milliseconds(1500)

    static func run(arguments: [String]) async -> Int32 {
        setvbuf(stdout, nil, _IOLBF, 0)
        guard let index = arguments.firstIndex(of: flag), arguments.count > index + 1 else {
            print("Kullanım: Asistan \(flag) <sorular.tsv> [lmstudio:<model> | vmlx:<yayıncı/model>]")
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
        let onDemand = arguments.contains(onDemandFlag)
        var choice: LocalModelChoice?
        let sameConversation = arguments.contains(sameConversationFlag)
        if arguments.count > index + 2, !arguments[index + 2].hasPrefix("--") {
            guard let parsed = LocalModelChoice(storageKey: arguments[index + 2]) else {
                print("Model biçimi: lmstudio:<model> ya da vmlx:<yayıncı/model>")
                return 2
            }
            choice = parsed
            if parsed.server == .builtIn, !BuiltInChatModel.isAvailable(parsed) {
                guard await download(parsed.modelID) else { return 1 }
            }
            brain.setLocalModelKeepAlive(onDemand ? .untilConversationEnds : .always)
            brain.useLocalModel(parsed)
            if !onDemand, await !brain.waitForLocalModel() {
                print("Model hazırlanamadı: \(arguments[index + 2])")
                return 1
            }
        }
        var passed = 0
        var firstChunkTimes: [Double] = []
        for (question, keys) in cases {
            let startsConversation = !sameConversation || question == cases.first?.0
            if startsConversation { brain.endConversation() }
            if onDemand, startsConversation {
                brain.conversationWillStart()
                try? await Task.sleep(for: simulatedSpeech)
            }
            let started = Date()
            var answer = ""
            var firstChunk: Double?
            var firstAnswerChunk: Double?
            do {
                for try await chunk in brain.respond(to: question) {
                    firstChunk = firstChunk ?? Date.now.timeIntervalSince(started)
                    if chunk != LocalModelResponder.waitingNotice {
                        firstAnswerChunk = firstAnswerChunk ?? Date.now.timeIntervalSince(started)
                    }
                    answer += chunk
                }
            } catch {
                answer = "HATA: \(error)"
            }
            let total = Date.now.timeIntervalSince(started)
            let hit = keys.contains { TurkishText.lowercased(answer).contains($0) }
            passed += hit ? 1 : 0
            firstChunkTimes.append(firstChunk ?? total)
            let timing = firstAnswerChunk == firstChunk
                ? String(format: "%.2f/%.2fs", firstChunk ?? -1, total)
                : String(format: "%.2f, yanıt %.2f/%.2fs", firstChunk ?? -1, firstAnswerChunk ?? -1, total)
            print("\(hit ? "✓" : "✗") [\(timing)] \(question) → \(answer.replacingOccurrences(of: "\n", with: " ").prefix(140))")
            if onDemand, let choice, !sameConversation || question == cases.last?.0 {
                brain.endConversation()
                try? await Task.sleep(for: .seconds(6))
                print("   konuşma bitti, model \(await isLoaded(choice) ? "hâlâ açık" : "kapandı")")
            }
        }
        let median = firstChunkTimes.sorted()[firstChunkTimes.count / 2]
        print(String(format: "Doğru: %d/%d · ilk yanıt parçası medyan %.2f sn", passed, cases.count, median))
        brain.shutDownLocalModel()
        return 0
    }

    private static func download(_ id: String) async -> Bool {
        guard let model = ModelCatalog.model(id: id) else {
            print("Katalogda yok: \(id)")
            return false
        }
        let started = Date()
        let reported = Mutex(-1)
        do {
            try await HuggingFaceDownloader().download(model, into: try ModelDownloads.folder(for: model)) { progress in
                let percent = Int(progress.fraction * 100) / 10 * 10
                if reported.withLock({ defer { $0 = percent }; return $0 != percent }) { print("   indiriliyor %\(percent)") }
            }
            print(String(format: "   indirildi: %.0f sn", Date.now.timeIntervalSince(started)))
            return true
        } catch {
            print("İndirilemedi: \(error.localizedDescription)")
            return false
        }
    }

    private static func isLoaded(_ choice: LocalModelChoice) async -> Bool {
        switch choice.server {
        case .lmStudio:
            let models = (try? await LMStudioClient().chatModels()) ?? []
            return models.contains { $0.id == choice.modelID && $0.isLoaded }
        case .vmlx:
            return await VMLXServer.awakeModels().contains(choice.modelID)
        case .builtIn, .custom, .folder:
            return BuiltInChatModel.isLoaded(choice)
        }
    }
}
