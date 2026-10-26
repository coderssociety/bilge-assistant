import Foundation

/// Renders messages in the ChatML format used by Qwen models, with the reasoning block already
/// closed so the model answers at once instead of thinking for seconds first.
public enum ChatMLPrompt {
    public static let stopSequences = ["<|im_end|>", "<|im_start|>"]
    private static let controlTokens = ["<|im_start|>", "<|im_end|>", "<|endoftext|>", "<think>", "</think>"]

    public static func render(_ messages: [ChatMessage]) -> String {
        let turns = messages.map { "<|im_start|>\($0.role.rawValue)\n\(sanitized($0.content))<|im_end|>\n" }
        return turns.joined() + "<|im_start|>assistant\n<think>\n\n</think>\n\n"
    }

    /// Text from the user or the screen must not be able to open or close turns of its own.
    /// Repeats until stable: removing one token must not assemble another ("<|im_st<think>art|>").
    static func sanitized(_ content: String) -> String {
        var current = content
        while true {
            let next = controlTokens.reduce(current) { $0.replacingOccurrences(of: $1, with: "") }
            if next == current { return current }
            current = next
        }
    }
}
