import AsistanCore

/// A conversation model ready to answer: served on this Mac over HTTP, or running inside Bilge.
protocol LoadedChatModel: Sendable {
    /// Streams the reply text.
    func streamReply(messages: [ChatMessage], temperature: Double, maxTokens: Int) -> AsyncThrowingStream<String, any Error>
    /// Pays the one-off cost of the first generation; a server with a prompt cache also keeps the instructions.
    func warmUp(instructions: String) async throws
}
