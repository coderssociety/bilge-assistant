import Foundation

enum AppleScriptError: LocalizedError {
    case compilationFailed
    case executionFailed(code: Int, message: String)

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
        }
    }
}

/// NSAppleScript is not thread-safe, so every script runs on the main actor.
/// Scripts are fixed templates; user or model text is only ever inserted through `quoted(_:)`.
enum AppleScriptRunner {
    /// Apple events otherwise wait up to two minutes for a busy app or an unanswered permission
    /// prompt, with the main thread blocked all the while.
    private static let timeoutSeconds = 20

    @MainActor
    static func run(_ source: String) throws -> String {
        let bounded = "with timeout of \(timeoutSeconds) seconds\n\(source)\nend timeout"
        guard let script = NSAppleScript(source: bounded) else { throw AppleScriptError.compilationFailed }
        var errorInfo: NSDictionary?
        let result = script.executeAndReturnError(&errorInfo)
        if let errorInfo {
            let code = errorInfo[NSAppleScript.errorNumber] as? Int ?? 0
            let message = errorInfo[NSAppleScript.errorMessage] as? String ?? "Bilinmeyen AppleScript hatası"
            throw AppleScriptError.executionFailed(code: code, message: message)
        }
        return result.stringValue ?? ""
    }

    /// Produces an AppleScript string literal; escapes backslashes and quotes so text cannot break out.
    static func quoted(_ text: String) -> String {
        let escaped = text
            .replacingOccurrences(of: "\\", with: "\\\\")
            .replacingOccurrences(of: "\"", with: "\\\"")
            .replacingOccurrences(of: "\r", with: " ")
        return "\"\(escaped)\""
    }
}
