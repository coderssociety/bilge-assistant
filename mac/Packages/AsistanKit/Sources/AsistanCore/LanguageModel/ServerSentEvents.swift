import Foundation

/// One line of an OpenAI-style `text/event-stream` response.
public enum ServerSentEventLine: Equatable, Sendable {
    case data(String)
    case done
    case ignored

    public init(_ line: String) {
        guard line.hasPrefix("data:") else {
            self = .ignored
            return
        }
        let payload = line.dropFirst("data:".count).trimmingCharacters(in: .whitespaces)
        if payload == "[DONE]" {
            self = .done
        } else if payload.isEmpty {
            self = .ignored
        } else {
            self = .data(payload)
        }
    }
}
