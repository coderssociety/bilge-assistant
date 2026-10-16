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
        /// Said during a work session without the wake phrase: input for that work (a cell edit, text
        /// to type) rather than a command to the assistant.
        case runWorkInput(String)
        case returnToIdle(timedOut: Bool)
    }

    /// Both languages' phrases: none of them means anything else in the other language.
    private static let cancelPhrases: Set<String> = [
        "iptal", "iptal et", "vazgec", "vazgectim", "bos ver", "bosver", "bir sey yok", "yok bir sey", "unut gitsin",
        "cancel", "never mind", "nevermind", "forget it",
    ]
    /// Also end a window, but are ordinary words while dictating, so a work session takes them as input.
    private static let outsideWorkCancelPhrases: Set<String> = [
        "nothing", "that s all", "thats all", "stop", "stop it", "be quiet", "quiet", "shut up", "enough",
    ]

    private static func cancels(_ key: String, inWork: Bool) -> Bool {
        cancelPhrases.contains(key) || (!inWork && outsideWorkCancelPhrases.contains(key))
    }

    /// A stretch of hands-free work, such as editing a spreadsheet: the window stays open longer, and
    /// without the wake phrase only what `accepts` recognizes is taken as a command, so talk in the
    /// room is not acted on.
    public struct WorkSession: Sendable {
        public let window: TimeInterval
        public let accepts: @Sendable (String) -> Bool

        public init(window: TimeInterval, accepts: @escaping @Sendable (String) -> Bool) {
            self.window = window
            self.accepts = accepts
        }
    }

    public private(set) var phase: Phase = .listeningForWake
    private var session: WorkSession?
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
            // "Bilge, stop" while nothing is going on has nothing to stop; it is not a command to route.
            if Self.cancels(TurkishText.folded(match.command), inWork: false) { return .none }
            return run(match.command)
        case .awaitingCommand, .followUp:
            let wakeMatch = matcher.match(transcript)
            let command = wakeMatch?.command ?? transcript.trimmingCharacters(in: .whitespacesAndNewlines)
            let key = TurkishText.folded(command)
            guard !key.isEmpty else { return .none }
            if case .followUp = phase, let session, wakeMatch == nil, !Self.cancels(key, inWork: true) {
                guard session.accepts(command) else { return .none }
                phase = .processing
                return .runWorkInput(command)
            }
            if Self.cancels(key, inWork: false) {
                session = nil
                phase = .listeningForWake
                return .returnToIdle(timedOut: false)
            }
            return run(command)
        case .processing, .responding:
            return .none
        }
    }

    /// The listening shortcut: like the wake phrase said on its own, and pressed again while the assistant waits
    /// for the request, a cancel. While it is answering this changes nothing.
    public mutating func shortcutPressed(at now: Date) -> Action {
        switch phase {
        case .awaitingCommand:
            speechInProgress = false
            phase = .listeningForWake
            return .returnToIdle(timedOut: false)
        case .listeningForWake, .followUp:
            session = nil
            phase = .awaitingCommand(deadline: now.addingTimeInterval(commandTimeout))
            return .acknowledgeWake
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
            session = nil
            phase = .listeningForWake
            return .returnToIdle(timedOut: false)
        default:
            return .none
        }
    }

    public mutating func responseStarted() {
        phase = .responding
    }

    public mutating func responseFinished(at now: Date, allowFollowUp: Bool, session: WorkSession? = nil) {
        speechInProgress = false
        self.session = session
        if let session {
            phase = .followUp(deadline: now.addingTimeInterval(session.window))
        } else {
            phase = allowFollowUp ? .followUp(deadline: now.addingTimeInterval(followUpWindow)) : .listeningForWake
        }
    }

    /// Abandons whatever is happening (errors, user stop) and listens for the wake phrase again.
    public mutating func reset() {
        speechInProgress = false
        session = nil
        phase = .listeningForWake
    }

    private mutating func run(_ command: String) -> Action {
        phase = .processing
        return .runCommand(command)
    }
}
