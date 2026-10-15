import AsistanCore
import Foundation

/// The assistant's language for this run of the app. It changes only with a restart
/// (`AssistantSettings.chooseLanguage`), so code far from the settings, such as tools that format dates
/// and numbers, reads it here.
enum AppLanguage {
    static let defaultsKey = "assistantLanguage"

    /// Benchmarks pass `--language en`; the app uses the stored choice.
    static let current: AssistantLanguage = resolve(arguments: CommandLine.arguments, defaults: .standard)

    static var locale: Locale { current.locale }

    private static let appleLanguagesKey = "AppleLanguages"
    /// Passed to the relaunched copy, so a localization that still disagrees cannot loop.
    static let relaunchedFlag = "--relaunched-for-language"

    /// Keeps the stored language and the app's localization together. A new user's language is stored as
    /// soon as it is known, and a Mac whose own language differs gets the app's localization pinned; if this
    /// run already loaded the other localization, the app restarts once.
    @MainActor
    static func alignLocalization(arguments: [String] = CommandLine.arguments) {
        // Benchmarks and `--language` runs choose their language for that run only; they must never
        // change what the user picked.
        let isBenchmark = arguments.contains { $0.hasPrefix("--bench") }
        guard !isBenchmark, !arguments.contains("--language") else { return }
        let defaults = UserDefaults.standard
        defaults.set(current.rawValue, forKey: defaultsKey)
        let domain = Bundle.main.bundleIdentifier.flatMap(defaults.persistentDomain(forName:))
        if (domain?[appleLanguagesKey] as? [String])?.first != current.code {
            defaults.set([current.code], forKey: appleLanguagesKey)
        }
        guard !arguments.contains(relaunchedFlag),
              Bundle.main.preferredLocalizations.first != current.code else { return }
        Log.app.info("Localization differs from the assistant's language; restarting")
        Task { @MainActor in AppRelauncher.relaunch(arguments: [relaunchedFlag]) }
    }

    /// Before languages existed everyone who finished setup used Turkish; a new user starts with the Mac's language.
    static func resolve(arguments: [String], defaults: UserDefaults) -> AssistantLanguage {
        if let index = arguments.firstIndex(of: "--language"), arguments.indices.contains(index + 1),
           let language = AssistantLanguage(rawValue: arguments[index + 1]) {
            return language
        }
        // Benchmarks are Turkish unless told otherwise, whatever the user or the Mac uses.
        if arguments.contains(where: { $0.hasPrefix("--bench") }) { return .turkish }
        if let stored = defaults.string(forKey: defaultsKey).flatMap(AssistantLanguage.init(rawValue:)) { return stored }
        if defaults.bool(forKey: "onboardingCompleted") { return .turkish }
        return AssistantLanguage.preferred(from: Locale.preferredLanguages)
    }
}
