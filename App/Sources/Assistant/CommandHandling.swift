import Foundation

/// Streams the spoken reply for one user command; fragments are spoken as soon as they form sentences.
@MainActor
protocol CommandHandling: AnyObject {
    func respond(to command: String) -> AsyncThrowingStream<String, any Error>
    /// Clears conversational context, e.g. when the user goes quiet and the exchange is over.
    func endConversation()
}

/// Placeholder until the language model is wired in: repeats what it heard so the audio loop can be tested.
@MainActor
final class EchoCommandHandler: CommandHandling {
    func respond(to command: String) -> AsyncThrowingStream<String, any Error> {
        AsyncThrowingStream { continuation in
            continuation.yield("Şunu duydum: \(command)")
            continuation.finish()
        }
    }

    func endConversation() {}
}
