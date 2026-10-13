import AsistanCore
import Foundation

enum AppleScriptError: LocalizedError {
    case compilationFailed
    case executionFailed(code: Int, message: String)
    case processFailed(status: Int32)

    static let notAuthorizedCode = -1743
    static let timedOutCode = -1712

    var errorDescription: String? {
        switch self {
        case .compilationFailed:
            "Betik derlenemedi."
        case let .executionFailed(code, _) where code == Self.timedOutCode:
            "Uygulama zamanında yanıt vermedi."
        case let .executionFailed(code, _) where code == Self.notAuthorizedCode:
            "Bu uygulamayı kontrol etme izni yok. Sistem Ayarları > Gizlilik ve Güvenlik > Otomasyon'dan izin verilmeli."
        case let .executionFailed(_, message):
            message
        case .processFailed:
            "Uygulama zamanında yanıt vermedi."
        }
    }
}

/// Scripts run in a separate `osascript` process, so a busy app or an unanswered permission prompt
/// never blocks the main thread, and cancelling the turn (barge-in) kills a script that hangs.
/// Automation permission is still Bilge's: TCC attributes a child process's Apple events to the app
/// that launched it. Scripts are fixed templates; user or model text is only ever inserted through
/// `quoted(_:)`, and the source goes through standard input, so message text never shows in `ps`.
enum AppleScriptRunner {
    private static let osascript = "/usr/bin/osascript"
    /// Apple events otherwise wait up to two minutes for a busy app or an unanswered permission prompt.
    private static let timeoutSeconds = 20
    /// Backstop for a script stuck outside an Apple event; AppleScript's own timeout fires first.
    private static let processTimeout: Duration = .seconds(timeoutSeconds + 5)
    /// osascript prints an absent result as this text, where NSAppleScript gave no string at all.
    private static let missingValue = "missing value"

    static func run(_ source: String) async throws -> String {
        let bounded = "with timeout of \(timeoutSeconds) seconds\n\(source)\nend timeout"
        let output = try await ProcessRunner.run(osascript, [], input: Data(bounded.utf8), timeout: processTimeout)
        guard output.status == 0 else { throw error(from: output) }
        return output.standardOutput == missingValue ? "" : output.standardOutput
    }

    /// For confirmed sends: the script finishes even if the turn is cancelled, because a killed script
    /// may already have handed the message over and the user would be told it was not sent.
    static func runToCompletion(_ source: String) async throws {
        _ = try await Task { try await run(source) }.value
    }

    /// Produces an AppleScript string literal; escapes backslashes and quotes so text cannot break out.
    static func quoted(_ text: String) -> String {
        let escaped = text
            .replacingOccurrences(of: "\\", with: "\\\\")
            .replacingOccurrences(of: "\"", with: "\\\"")
            .replacingOccurrences(of: "\r", with: " ")
        return "\"\(escaped)\""
    }

    private static func error(from output: ProcessRunner.Output) -> AppleScriptError {
        guard let failure = ScriptErrorOutput.parse(output.standardError) else {
            Log.tools.error("osascript exited with \(output.status): \(output.standardError)")
            return .processFailed(status: output.status)
        }
        switch failure.kind {
        case .syntax:
            Log.tools.error("AppleScript did not compile: \(failure.message)")
            return .compilationFailed
        case .execution:
            return .executionFailed(code: failure.code, message: failure.message)
        }
    }
}
