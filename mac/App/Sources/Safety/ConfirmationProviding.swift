import AsistanCore

/// Asks the user a yes/no question out loud (or via the menu) in the middle of a turn.
@MainActor
protocol ConfirmationProviding: AnyObject {
    /// `strict` accepts only an explicit "evet"/"gönder" (yes/send) (see `ConfirmationParser`).
    func confirm(_ question: String, strict: Bool) async -> ConfirmationParser.Answer
}
