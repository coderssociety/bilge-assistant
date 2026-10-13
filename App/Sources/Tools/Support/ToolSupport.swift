import Foundation
import FoundationModels

enum ToolRisk: Sendable, Equatable {
    /// Read-only or easily undone; runs without asking.
    case safe
    /// Irreversible or leaves the Mac (deletes, sends, runs commands); the user must confirm out loud.
    case needsConfirmation
}

/// A Mac action the assistant can take. Results are short Turkish sentences that are spoken as-is;
/// failures are reported as text (see `ToolReply`) rather than thrown.
protocol AssistantTool: Tool where Output == String, Arguments: Generable & Sendable {
    var risk: ToolRisk { get }
    /// The result is raw material (screen text) that the language model turns into the answer.
    var answersWithLanguageModel: Bool { get }
    /// Non-nil for tools without parameters, so the router can skip argument extraction.
    func emptyArguments() -> Arguments?
    /// Lets a tool replace model-extracted values with ones parsed deterministically from the
    /// (number- and time-resolved) command text.
    func refine(_ arguments: Arguments, command: String) -> Arguments
    /// Binds arguments into an executable call. Tools that must resolve something first (which file,
    /// which shortcut) override this so the confirmation question names exactly what will be acted on.
    func makeCall(_ arguments: Arguments) async -> PreparedToolCall
    /// The yes/no question for `.needsConfirmation` tools, e.g. "…takvime ekleyeyim mi?".
    func confirmationQuestion(for arguments: Arguments) -> String
}

extension AssistantTool {
    var risk: ToolRisk { .safe }
    var answersWithLanguageModel: Bool { false }
    func emptyArguments() -> Arguments? { nil }
    func refine(_ arguments: Arguments, command: String) -> Arguments { arguments }
    func confirmationQuestion(for arguments: Arguments) -> String { "Bunu yapmamı onaylıyor musun?" }

    func makeCall(_ arguments: Arguments) async -> PreparedToolCall {
        PreparedToolCall(
            toolName: name,
            argumentsDescription: String(describing: arguments),
            risk: risk,
            confirmationQuestion: risk == .needsConfirmation ? confirmationQuestion(for: arguments) : nil,
            answersWithLanguageModel: answersWithLanguageModel,
            execute: { try await call(arguments: arguments) })
    }
}

/// A tool call whose arguments are already resolved; executing it is a separate, deliberate step.
struct PreparedToolCall: Sendable {
    let toolName: String
    let argumentsDescription: String
    let risk: ToolRisk
    let confirmationQuestion: String?
    var answersWithLanguageModel = false
    let execute: @Sendable () async throws -> String

    /// A call that cannot run (e.g. nothing matched); speaking `message` is the whole turn.
    static func unavailable(_ toolName: String, message: String) -> PreparedToolCall {
        PreparedToolCall(toolName: toolName, argumentsDescription: "", risk: .safe, confirmationQuestion: nil,
                         execute: { ToolReply.failure(message) })
    }
}

enum ToolReply {
    private static let failurePrefix = "BAŞARISIZ: "

    static func failure(_ message: String) -> String {
        failurePrefix + message
    }

    static func isFailure(_ result: String) -> Bool {
        result.hasPrefix(failurePrefix)
    }

    /// Turns a tool result into what the assistant says out loud.
    static func spoken(_ result: String) -> String {
        guard result.hasPrefix(failurePrefix) else { return result }
        return "Bunu yapamadım. " + result.dropFirst(failurePrefix.count)
    }

    static func failure(_ error: any Error) -> String {
        failure(error.localizedDescription)
    }
}

enum ProcessRunner {
    struct Output: Sendable {
        let status: Int32
        let standardOutput: String
        let standardError: String
    }

    static let defaultTimeout: Duration = .seconds(15)

    /// Runs a fixed executable with discrete arguments (never through a shell) and captures its output.
    static func run(_ executable: String, _ arguments: [String], timeout: Duration = defaultTimeout) async throws -> Output {
        let process = Process()
        process.executableURL = URL(filePath: executable)
        process.arguments = arguments
        let stdout = Pipe()
        let stderr = Pipe()
        process.standardOutput = stdout
        process.standardError = stderr

        try process.run()
        let timeoutTask = Task {
            try await Task.sleep(for: timeout)
            if process.isRunning { process.terminate() }
        }
        defer { timeoutTask.cancel() }

        async let outData = Task.detached { stdout.fileHandleForReading.readDataToEndOfFile() }.value
        async let errData = Task.detached { stderr.fileHandleForReading.readDataToEndOfFile() }.value
        let (out, err) = await (outData, errData)
        process.waitUntilExit()
        return Output(
            status: process.terminationStatus,
            standardOutput: String(decoding: out, as: UTF8.self).trimmingCharacters(in: .whitespacesAndNewlines),
            standardError: String(decoding: err, as: UTF8.self).trimmingCharacters(in: .whitespacesAndNewlines))
    }
}
