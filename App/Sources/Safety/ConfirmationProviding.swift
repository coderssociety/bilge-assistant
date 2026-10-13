import AsistanCore

/// Asks the user a yes/no question out loud (or via the menu) in the middle of a turn.
@MainActor
protocol ConfirmationProviding: AnyObject {
    func confirm(_ question: String) async -> ConfirmationParser.Answer
}
