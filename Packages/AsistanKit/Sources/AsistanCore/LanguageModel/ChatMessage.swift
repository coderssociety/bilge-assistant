public struct ChatMessage: Sendable, Equatable {
    public enum Role: String, Sendable {
        case system, user, assistant
    }

    public let role: Role
    public let content: String

    public init(role: Role, content: String) {
        self.role = role
        self.content = content
    }

    public static func system(_ content: String) -> ChatMessage { ChatMessage(role: .system, content: content) }
    public static func user(_ content: String) -> ChatMessage { ChatMessage(role: .user, content: content) }
    public static func assistant(_ content: String) -> ChatMessage { ChatMessage(role: .assistant, content: content) }
}

/// The recent exchanges of a conversation, oldest first. Bounded so prompts stay short and fast.
public struct ChatHistory: Sendable, Equatable {
    public let maxExchanges: Int
    public private(set) var messages: [ChatMessage] = []

    public init(maxExchanges: Int = 6) {
        self.maxExchanges = max(1, maxExchanges)
    }

    public func appending(user: String, assistant: String) -> ChatHistory {
        var next = self
        next.messages = Array((messages + [.user(user), .assistant(assistant)]).suffix(maxExchanges * 2))
        return next
    }
}
