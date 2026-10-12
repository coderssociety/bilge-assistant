import Foundation

/// Pure turn-taking logic: when to wake, when a transcript is a command, and when to go back to sleep.
public struct ConversationFlow: Sendable {
    public enum Phase: Sendable, Equatable {
        case listeningForWake
        case awaitingCommand(deadline: Date)
        case processing
        case responding
        case followUp(deadline: Date)
    }

    public enum Action: Sendable, Equatable {
        case none
        case acknowledgeWake
        case runCommand(String)
        case returnToIdle(timedOut: Bool)
    }

    private static let cancelPhrases: Set<String> = [
        "iptal", "iptal et", "vazgec", "vazgectim", "bos ver", "bosver", "bir sey yok", "yok bir sey", "unut gitsin",
    ]

    public private(set) var phase: Phase = .listeningForWake
    public var matcher: WakePhraseMatcher
    public var commandTimeout: TimeInterval
    public var followUpWindow: TimeInterval
    private var speechInProgress = false

    public init(matcher: WakePhraseMatcher, commandTimeout: TimeInterval = 6, followUpWindow: TimeInterval = 6) {
        self.matcher = matcher
        self.commandTimeout = commandTimeout
        self.followUpWindow = followUpWindow
    }

    public var isAwaitingSpeech: Bool {
        switch phase {
        case .awaitingCommand, .followUp: true
        default: false
        }
    }

    public mutating func heard(_ transcript: String, at now: Date) -> Action {
        speechInProgress = false
        switch phase {
        case .listeningForWake:
            guard let match = matcher.match(transcript) else { return .none }
            if match.command.isEmpty {
                phase = .awaitingCommand(deadline: now.addingTimeInterval(commandTimeout))
                return .acknowledgeWake
            }
            return run(match.command)
        case .awaitingCommand, .followUp:
            let command = matcher.match(transcript)?.command ?? transcript.trimmingCharacters(in: .whitespacesAndNewlines)
            let key = TurkishText.folded(command)
            guard !key.isEmpty else { return .none }
            if Self.cancelPhrases.contains(key) {
                phase = .listeningForWake
                return .returnToIdle(timedOut: false)
            }
            return run(command)
        case .processing, .responding:
            return .none
        }
    }

    /// Once the user starts talking inside a window, the deadline no longer cuts them off.
    public mutating func speechStarted(at now: Date) {
        if isAwaitingSpeech { speechInProgress = true }
    }

    public mutating func tick(at now: Date) -> Action {
        guard !speechInProgress else { return .none }
        switch phase {
        case let .awaitingCommand(deadline) where now >= deadline:
            phase = .listeningForWake
            return .returnToIdle(timedOut: true)
        case let .followUp(deadline) where now >= deadline:
            phase = .listeningForWake
            return .returnToIdle(timedOut: false)
        default:
            return .none
        }
    }

    public mutating func responseStarted() {
        phase = .responding
    }

    public mutating func responseFinished(at now: Date, allowFollowUp: Bool) {
        speechInProgress = false
        phase = allowFollowUp ? .followUp(deadline: now.addingTimeInterval(followUpWindow)) : .listeningForWake
    }

    /// Abandons whatever is happening (errors, user stop) and listens for the wake phrase again.
    public mutating func reset() {
        speechInProgress = false
        phase = .listeningForWake
    }

    private mutating func run(_ command: String) -> Action {
        phase = .processing
        return .runCommand(command)
    }
}
