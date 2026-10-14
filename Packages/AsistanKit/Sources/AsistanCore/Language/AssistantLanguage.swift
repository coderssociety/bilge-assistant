import Foundation

/// The language the assistant listens, speaks and shows its menus in; chosen during setup.
public enum AssistantLanguage: String, CaseIterable, Sendable, Codable {
    case turkish = "tr"
    case english = "en"

    /// ISO 639-1 code, as speech recognizers and the synthesizer expect it.
    public var code: String { rawValue }

    public var locale: Locale {
        switch self {
        case .turkish: Locale(identifier: "tr_TR")
        case .english: Locale(identifier: "en_US")
        }
    }

    /// The language's own name, so it reads right whichever language is active.
    public var nativeName: String {
        switch self {
        case .turkish: "Türkçe"
        case .english: "English"
        }
    }

    /// The language matching the Mac's preferred languages, Turkish otherwise.
    public static func preferred(from identifiers: [String]) -> AssistantLanguage {
        for identifier in identifiers {
            let code = Locale(identifier: identifier).language.languageCode?.identifier
            if let language = allCases.first(where: { $0.code == code }) { return language }
        }
        return .turkish
    }
}
