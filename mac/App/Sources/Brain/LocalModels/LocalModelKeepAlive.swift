import Foundation

/// How long a large conversation model stays in memory after it was used.
enum LocalModelKeepAlive: String, CaseIterable, Sendable {
    /// Loaded when the wake phrase is heard, freed as soon as the exchange is over.
    case untilConversationEnds
    case fiveMinutes
    case thirtyMinutes
    /// Loaded at launch and kept.
    case always

    var idleLimit: Duration? {
        switch self {
        case .untilConversationEnds: .zero
        case .fiveMinutes: .seconds(5 * 60)
        case .thirtyMinutes: .seconds(30 * 60)
        case .always: nil
        }
    }

    var displayName: String {
        switch self {
        case .untilConversationEnds: String(localized: "Konuşma bitince kapat")
        case .fiveMinutes: String(localized: "5 dakika boşta kalınca kapat")
        case .thirtyMinutes: String(localized: "30 dakika boşta kalınca kapat")
        case .always: String(localized: "Hep açık tut")
        }
    }
}
