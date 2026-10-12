import Foundation
import FoundationModels

/// Headless routing benchmark: `Asistan --bench-llm <commands.tsv> <output-dir>`.
/// Each line is "command<TAB>expected action[,alternative]"; "conversation" means no tool.
/// Tools are prepared (arguments extracted) but never executed.
@MainActor
enum LLMBenchmark {
    static let flag = "--bench-llm"

    struct CaseResult: Codable {
        let command: String
        let expected: [String]
        let action: String
        let arguments: String?
        let seconds: Double
        let passed: Bool
        let error: String?
    }

    static func run(arguments: [String]) async -> Int32 {
        setvbuf(stdout, nil, _IOLBF, 0)
        guard let index = arguments.firstIndex(of: flag), arguments.count > index + 2 else {
            print("Kullanım: Asistan \(flag) <komutlar.tsv> <çıktı-klasörü>")
            return 2
        }
        let outputURL = URL(filePath: arguments[index + 2], directoryHint: .isDirectory)
        do {
            let cases = try loadCases(URL(filePath: arguments[index + 1]))
            let tools = ToolRegistry(catalog: AppCatalog(), timers: TimerService { _ in }).makeTools()
            let router = try CommandRouter(tools: tools)
            var results: [CaseResult] = []
            for (command, expected) in cases {
                let result = await evaluate(command, expected: expected, router: router)
                let mark = result.passed ? "✓" : "✗"
                print("\(mark) \(command) → \(result.action) \(result.arguments ?? "") (\(String(format: "%.2f", result.seconds))s)")
                results.append(result)
            }
            summarize(results)
            try write(results, to: outputURL)
            return 0
        } catch {
            print("Kıyas başarısız: \(error.localizedDescription)")
            return 1
        }
    }

    private static func evaluate(_ command: String, expected: [String], router: CommandRouter) async -> CaseResult {
        let started = Date()
        do {
            let route = try await router.route(command, previous: nil)
            let (action, arguments): (String, String?) = switch route {
            case let .tool(call): (call.toolName, call.argumentsDescription)
            case .conversation: (CommandRouter.conversationAction, nil)
            }
            return CaseResult(command: command, expected: expected, action: action, arguments: arguments,
                              seconds: Date.now.timeIntervalSince(started), passed: expected.contains(action), error: nil)
        } catch {
            return CaseResult(command: command, expected: expected, action: "error", arguments: nil,
                              seconds: Date.now.timeIntervalSince(started), passed: false, error: String(describing: error))
        }
    }

    private static func loadCases(_ url: URL) throws -> [(String, [String])] {
        try String(contentsOf: url, encoding: .utf8).split(whereSeparator: \.isNewline).compactMap { line in
            let parts = line.split(separator: "\t").map(String.init)
            guard parts.count == 2 else { return nil }
            return (parts[0], parts[1].split(separator: ",").map(String.init))
        }
    }

    private static func summarize(_ results: [CaseResult]) {
        let passed = results.filter(\.passed).count
        let times = results.map(\.seconds).sorted()
        let median = times.isEmpty ? 0 : times[times.count / 2]
        print(String(format: "Doğru eylem: %d/%d (%.0f%%)  medyan %.2fs  en kötü %.2fs",
                     passed, results.count, Double(passed) / Double(max(results.count, 1)) * 100, median, times.last ?? 0))
    }

    private static func write(_ results: [CaseResult], to directory: URL) throws {
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes]
        let url = directory.appending(path: "llm-report.json")
        try encoder.encode(results).write(to: url)
        print("Rapor: \(url.path)")
    }
}
