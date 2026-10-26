import AsistanCore
import Foundation

/// Streams the spoken reply for one user command; fragments are spoken as soon as they form sentences.
@MainActor
protocol CommandHandling: AnyObject {
    func respond(to command: String) -> AsyncThrowingStream<String, any Error>
    /// A routine's command, run with nobody there: nothing that needs a yes may happen.
    func respondUnattended(to command: String) -> AsyncThrowingStream<String, any Error>
    /// Clears conversational context, e.g. when the user goes quiet and the exchange is over.
    func endConversation()
    /// The wake phrase was heard; a command is about to follow.
    func conversationWillStart()
    /// Hands-free work in progress (Excel mode, dictation), which keeps listening after the reply.
    var workSession: ConversationFlow.WorkSession? { get }
    /// Something said during that work without the wake phrase: a cell edit, text to type, speech to interpret
    /// (`language` is the one it was recognized in, when the session detects languages).
    func respond(toWorkInput input: String, language: String?) -> AsyncThrowingStream<String, any Error>
    /// The language to speak the reply in, nil for the assistant's own.
    func replyLanguageCode(for input: String, isWorkInput: Bool, heard: String?) -> String?
}

extension CommandHandling {
    var workSession: ConversationFlow.WorkSession? { nil }

    func respond(toWorkInput input: String, language: String?) -> AsyncThrowingStream<String, any Error> {
        respond(to: input)
    }

    func replyLanguageCode(for input: String, isWorkInput: Bool, heard: String?) -> String? {
        isWorkInput ? nil : TranslationRequest.target(in: input)?.code
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

    func respondUnattended(to command: String) -> AsyncThrowingStream<String, any Error> {
        respond(to: command)
    }

    func endConversation() {}
    func conversationWillStart() {}
}
