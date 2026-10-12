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
    /// Non-nil for tools without parameters, so the router can skip argument extraction.
    func emptyArguments() -> Arguments?
    /// Lets a tool replace model-extracted values with ones parsed deterministically from the
    /// (number- and time-resolved) command text.
    func refine(_ arguments: Arguments, command: String) -> Arguments
}

extension AssistantTool {
    var risk: ToolRisk { .safe }
    func emptyArguments() -> Arguments? { nil }
    func refine(_ arguments: Arguments, command: String) -> Arguments { arguments }
}

/// A tool call whose arguments are already resolved; executing it is a separate, deliberate step.
struct PreparedToolCall: Sendable {
    let toolName: String
    let argumentsDescription: String
    let risk: ToolRisk
    let execute: @Sendable () async throws -> String
}

enum ToolReply {
    private static let failurePrefix = "BAŞARISIZ: "

    static func failure(_ message: String) -> String {
        failurePrefix + message
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
