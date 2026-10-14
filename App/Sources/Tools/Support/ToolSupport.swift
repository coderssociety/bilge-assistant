import Foundation
import FoundationModels
import Synchronization

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
    /// Non-nil when the whole command can serve as the arguments, skipping model extraction.
    func arguments(fromCommand command: String) -> Arguments?
    /// Lets a tool replace model-extracted values with ones parsed deterministically from the
    /// (number- and time-resolved) command text.
    func refine(_ arguments: Arguments, command: String) -> Arguments
    /// True when the refined arguments show the request was a question rather than this action
    /// ("bir haftada kaç saat var" routed to calculate without any numbers said).
    func prefersConversation(for arguments: Arguments) -> Bool
    /// Binds arguments into an executable call. Tools that must resolve something first (which file,
    /// which shortcut) override this so the confirmation question names exactly what will be acted on.
    func makeCall(_ arguments: Arguments) async -> PreparedToolCall
    /// The yes/no question for `.needsConfirmation` tools, e.g. "…takvime ekleyeyim mi?".
    func confirmationQuestion(for arguments: Arguments) -> String
}

/// A tool chosen by rules rather than by the router model, for commands where a guess would be wrong
/// (cell names, what "bu" points at, keys sent to a browser). It is never offered to the model.
protocol RuleRoutedTool: AssistantTool {
    @MainActor func claims(_ command: String) -> Bool
}

extension AssistantTool {
    var risk: ToolRisk { .safe }
    var answersWithLanguageModel: Bool { false }
    func emptyArguments() -> Arguments? { nil }
    func arguments(fromCommand command: String) -> Arguments? { nil }
    func refine(_ arguments: Arguments, command: String) -> Arguments { arguments }
    func prefersConversation(for arguments: Arguments) -> Bool { false }
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
    /// Sending on the user's behalf: only an explicit "evet"/"gönder" confirms.
    var requiresExplicitYes = false
    let execute: @Sendable () async throws -> String

    /// The same call with `note` spoken before its confirmation question.
    func cautioned(_ note: String) -> PreparedToolCall {
        PreparedToolCall(toolName: toolName, argumentsDescription: argumentsDescription, risk: risk,
                         confirmationQuestion: confirmationQuestion.map { note + " " + $0 },
                         answersWithLanguageModel: answersWithLanguageModel, requiresExplicitYes: requiresExplicitYes,
                         execute: execute)
    }

    /// The same call, but asking `question` first even if it was safe.
    func requiringConfirmation(_ question: String) -> PreparedToolCall {
        PreparedToolCall(toolName: toolName, argumentsDescription: argumentsDescription, risk: .needsConfirmation,
                         confirmationQuestion: question, answersWithLanguageModel: answersWithLanguageModel,
                         requiresExplicitYes: requiresExplicitYes, execute: execute)
    }

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
    private static let terminationGrace: Duration = .seconds(2)
    /// A child the process left behind can hold the pipes open; output is not awaited longer than this.
    private static let outputGrace: Duration = .milliseconds(500)

    /// Runs a fixed executable with discrete arguments (never through a shell) and captures its output.
    /// Always returns within `timeout` plus a few seconds, even if the process ignores SIGTERM;
    /// cancelling the calling task stops the process and throws `CancellationError`.
    /// `input` is written to standard input, which keeps it out of the process list, unlike arguments.
    static func run(_ executable: String, _ arguments: [String], input: Data? = nil,
                    timeout: Duration = defaultTimeout) async throws -> Output {
        let process = Process()
        process.executableURL = URL(filePath: executable)
        process.arguments = arguments
        let stdout = PipeCollector()
        let stderr = PipeCollector()
        defer {
            stdout.close()
            stderr.close()
        }
        process.standardOutput = stdout.pipe
        process.standardError = stderr.pipe
        let stdin = input.map { _ in Pipe() }
        if let stdin { process.standardInput = stdin }
        let exit = ExitSignal()
        process.terminationHandler = { _ in exit.signal() }

        try process.run()
        let watchdog = Task.detached {
            try await Task.sleep(for: timeout)
            Log.tools.error("\(executable, privacy: .public) timed out; terminating")
            await stop(process)
        }
        defer { watchdog.cancel() }
        if let input, let stdin {
            write(input, to: stdin.fileHandleForWriting, of: executable)
        }
        await withTaskCancellationHandler {
            await exit.wait()
        } onCancel: {
            Task.detached { await stop(process) }
        }
        try Task.checkCancellation()

        async let standardOutput = stdout.text(waitingUpTo: outputGrace)
        async let standardError = stderr.text(waitingUpTo: outputGrace)
        return Output(status: process.terminationStatus, standardOutput: await standardOutput, standardError: await standardError)
    }

    /// A process that exits before reading its input would otherwise kill the app with SIGPIPE;
    /// with F_SETNOSIGPIPE the write fails with EPIPE, and the exit status reports the failure.
    /// The watchdog is already running, so a process that never reads cannot block this past the timeout.
    private static func write(_ data: Data, to handle: FileHandle, of executable: String) {
        defer { try? handle.close() }
        _ = fcntl(handle.fileDescriptor, F_SETNOSIGPIPE, 1)
        do {
            try handle.write(contentsOf: data)
        } catch {
            Log.tools.error("Could not write input to \(executable, privacy: .public): \(error.localizedDescription, privacy: .public)")
        }
    }

    private static func stop(_ process: Process) async {
        guard process.isRunning else { return }
        process.terminate()
        try? await Task.sleep(for: terminationGrace)
        if process.isRunning { kill(process.processIdentifier, SIGKILL) }
    }
}

/// Resumes one waiter when the process exits, whichever happens first.
private final class ExitSignal: Sendable {
    private let state = Mutex<(exited: Bool, waiter: CheckedContinuation<Void, Never>?)>((false, nil))

    func signal() {
        let waiter = state.withLock { state in
            state.exited = true
            defer { state.waiter = nil }
            return state.waiter
        }
        waiter?.resume()
    }

    func wait() async {
        await withCheckedContinuation { continuation in
            let alreadyExited = state.withLock { state in
                if !state.exited { state.waiter = continuation }
                return state.exited
            }
            if alreadyExited { continuation.resume() }
        }
    }
}

private final class PipeCollector: Sendable {
    private final class Buffer: Sendable {
        static let maxBytes = 1 << 20
        let state = Mutex((data: Data(), reachedEnd: false))
    }

    let pipe = Pipe()
    private let buffer = Buffer()

    init() {
        pipe.fileHandleForReading.readabilityHandler = { [buffer] handle in
            let chunk = handle.availableData
            buffer.state.withLock { state in
                if chunk.isEmpty {
                    state.reachedEnd = true
                } else if state.data.count < Buffer.maxBytes {
                    state.data.append(chunk)
                }
            }
            if chunk.isEmpty { handle.readabilityHandler = nil }
        }
    }

    func text(waitingUpTo limit: Duration) async -> String {
        let deadline = ContinuousClock.now + limit
        while !buffer.state.withLock({ $0.reachedEnd }), ContinuousClock.now < deadline {
            try? await Task.sleep(for: .milliseconds(10))
        }
        close()
        let data = buffer.state.withLock { $0.data }
        return String(decoding: data, as: UTF8.self).trimmingCharacters(in: .whitespacesAndNewlines)
    }

    func close() {
        pipe.fileHandleForReading.readabilityHandler = nil
    }
}
