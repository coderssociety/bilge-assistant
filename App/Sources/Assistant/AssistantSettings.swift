import AsistanCore
import FluidAudio
import Foundation
import Observation

/// User preferences, persisted in UserDefaults. Changes take effect the next time listening starts.
@MainActor
@Observable
final class AssistantSettings {
    private enum Key {
        static let wakePhrase = "wakePhrase"
        static let wakeSensitivity = "wakeSensitivity"
        static let recognizer = "recognizer"
        static let voice = "voice"
        static let speechSpeed = "speechSpeed"
        static let followUpEnabled = "followUpEnabled"
        static let listenOnLaunch = "listenOnLaunch"
        static let showHUD = "showHUD"
        static let bargeInEnabled = "bargeInEnabled"
        static let localModelID = "localModelID"
        static let localModelKeepAlive = "localModelKeepAlive"
        static let weatherCity = WeatherTool.defaultCityKey
        static let onboardingCompleted = "onboardingCompleted"
        static let proactiveAlertsEnabled = "proactiveAlertsEnabled"
        static let eventAlertLeadMinutes = "eventAlertLeadMinutes"
        static let morningBriefingEnabled = BriefingTool.enabledKey
        static let speakerCheckEnabled = "speakerCheckEnabled"
        static let language = AppLanguage.defaultsKey
        /// The system key that picks the app's localization; set together with `language`.
        static let appleLanguages = "AppleLanguages"
    }

    static let eventAlertLeadChoices = [5, 10, 15, 30]

    private let defaults: UserDefaults

    /// Fixed for the app's run: menus follow it too, so switching restarts the app (`chooseLanguage`).
    let language: AssistantLanguage

    var wakePhrase: String { didSet { defaults.set(wakePhrase, forKey: Key.wakePhrase) } }
    /// 0...1 where higher accepts fuzzier matches (more triggers, more false alarms).
    var wakeSensitivity: Double { didSet { defaults.set(wakeSensitivity, forKey: Key.wakeSensitivity) } }
    var recognizer: RecognizerEngine { didSet { defaults.set(recognizer.rawValue, forKey: Key.recognizer) } }
    var voice: Supertonic3Voice { didSet { defaults.set(voice.rawValue, forKey: Key.voice) } }
    var speechSpeed: Float { didSet { defaults.set(speechSpeed, forKey: Key.speechSpeed) } }
    var followUpEnabled: Bool { didSet { defaults.set(followUpEnabled, forKey: Key.followUpEnabled) } }
    var listenOnLaunch: Bool { didSet { defaults.set(listenOnLaunch, forKey: Key.listenOnLaunch) } }
    var showHUD: Bool { didSet { defaults.set(showHUD, forKey: Key.showHUD) } }
    var bargeInEnabled: Bool { didSet { defaults.set(bargeInEnabled, forKey: Key.bargeInEnabled) } }
    /// `LocalModelChoice.storageKey` of the model for conversation and screen answers; nil means Apple's.
    var localModelID: String? { didSet { defaults.set(localModelID, forKey: Key.localModelID) } }

    var weatherCity: String { didSet { defaults.set(weatherCity, forKey: Key.weatherCity) } }
    var localModelKeepAlive: LocalModelKeepAlive {
        didSet { defaults.set(localModelKeepAlive.rawValue, forKey: Key.localModelKeepAlive) }
    }

    var localModel: LocalModelChoice? {
        localModelID.flatMap(LocalModelChoice.init(storageKey:))
    }
    var onboardingCompleted: Bool { didSet { defaults.set(onboardingCompleted, forKey: Key.onboardingCompleted) } }
    /// Speak upcoming calendar events and reminders that come due, while listening is on.
    var proactiveAlertsEnabled: Bool { didSet { defaults.set(proactiveAlertsEnabled, forKey: Key.proactiveAlertsEnabled) } }
    var eventAlertLeadMinutes: Int { didSet { defaults.set(eventAlertLeadMinutes, forKey: Key.eventAlertLeadMinutes) } }
    /// The first "günaydın" (good morning) of the day is answered with the day's summary.
    var morningBriefingEnabled: Bool { didSet { defaults.set(morningBriefingEnabled, forKey: Key.morningBriefingEnabled) } }
    /// Only the enrolled voice can give commands and answer confirmations.
    var speakerCheckEnabled: Bool { didSet { defaults.set(speakerCheckEnabled, forKey: Key.speakerCheckEnabled) } }

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        language = AppLanguage.resolve(arguments: CommandLine.arguments, defaults: defaults)
        wakePhrase = defaults.string(forKey: Key.wakePhrase) ?? AppIdentity.defaultWakePhrase
        wakeSensitivity = defaults.object(forKey: Key.wakeSensitivity) as? Double ?? 0.5
        recognizer = defaults.string(forKey: Key.recognizer).flatMap(RecognizerEngine.init(rawValue:))
            ?? RecognizerFactory.defaultEngine(for: language)
        voice = defaults.string(forKey: Key.voice).flatMap(Supertonic3Voice.init(rawValue:)) ?? .f1
        speechSpeed = defaults.object(forKey: Key.speechSpeed) as? Float ?? 1.05
        followUpEnabled = defaults.object(forKey: Key.followUpEnabled) as? Bool ?? true
        listenOnLaunch = defaults.object(forKey: Key.listenOnLaunch) as? Bool ?? false
        showHUD = defaults.object(forKey: Key.showHUD) as? Bool ?? true
        bargeInEnabled = defaults.object(forKey: Key.bargeInEnabled) as? Bool ?? true
        localModelID = defaults.string(forKey: Key.localModelID)
        weatherCity = defaults.string(forKey: Key.weatherCity) ?? WeatherTool.fallbackCity
        localModelKeepAlive = defaults.string(forKey: Key.localModelKeepAlive)
            .flatMap(LocalModelKeepAlive.init(rawValue:)) ?? .untilConversationEnds
        onboardingCompleted = defaults.bool(forKey: Key.onboardingCompleted)
        proactiveAlertsEnabled = defaults.object(forKey: Key.proactiveAlertsEnabled) as? Bool ?? true
        eventAlertLeadMinutes = defaults.object(forKey: Key.eventAlertLeadMinutes) as? Int ?? 10
        morningBriefingEnabled = defaults.object(forKey: Key.morningBriefingEnabled) as? Bool ?? true
        speakerCheckEnabled = defaults.bool(forKey: Key.speakerCheckEnabled)
    }

    /// Maps the 0...1 sensitivity slider onto the matcher's similarity threshold (0.9 strict ... 0.65 loose).
    var minimumWakeSimilarity: Double {
        0.9 - 0.25 * min(max(wakeSensitivity, 0), 1)
    }

    /// Saves the language and the matching app localization; it takes effect when the app next starts.
    func chooseLanguage(_ language: AssistantLanguage) {
        defaults.set(language.rawValue, forKey: Key.language)
        defaults.set([language.code], forKey: Key.appleLanguages)
        // The best recognizer differs by language (see `RecognizerFactory.defaultEngine`).
        defaults.removeObject(forKey: Key.recognizer)
    }

    func makeWakeMatcher() -> WakePhraseMatcher {
        WakePhraseMatcher(phrase: wakePhrase, minimumSimilarity: minimumWakeSimilarity)
    }
}
