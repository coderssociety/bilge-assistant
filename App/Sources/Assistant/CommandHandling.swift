import AsistanCore
import Foundation

/// Streams the spoken reply for one user command; fragments are spoken as soon as they form sentences.
@MainActor
protocol CommandHandling: AnyObject {
    func respond(to command: String) -> AsyncThrowingStream<String, any Error>
    /// Clears conversational context, e.g. when the user goes quiet and the exchange is over.
    func endConversation()
    /// The wake phrase was heard; a command is about to follow.
    func conversationWillStart()
    /// Hands-free work in progress (Excel mode, dictation), which keeps listening after the reply.
    var workSession: ConversationFlow.WorkSession? { get }
    /// Something said during that work without the wake phrase: a cell edit, text to type.
    func respond(toWorkInput input: String) -> AsyncThrowingStream<String, any Error>
}

extension CommandHandling {
    var workSession: ConversationFlow.WorkSession? { nil }

    func respond(toWorkInput input: String) -> AsyncThrowingStream<String, any Error> {
        respond(to: input)
    }
}

/// Placeholder until the language model is wired in: repeats what it heard so the audio loop can be tested.
@MainActor
final class EchoCommandHandler: CommandHandling {
    func respond(to command: String) -> AsyncThrowingStream<String, any Error> {
        AsyncThrowingStream { continuation in
            continuation.yield(String(localized: "Şunu duydum: \(command)"))
            continuation.finish()
        }
    }

    func endConversation() {}
    func conversationWillStart() {}
}
