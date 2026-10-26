import AsistanCore
import SwiftUI

@main
struct AsistanApp: App {
    @State private var environment = AppEnvironment()

    init() {
        AppLanguage.alignLocalization()
        let arguments = CommandLine.arguments
        if arguments.contains(ASRBenchmark.flag) {
            Task { @MainActor in exit(await ASRBenchmark.run(arguments: arguments)) }
        } else if arguments.contains(LLMBenchmark.flag) {
            Task { @MainActor in exit(await LLMBenchmark.run(arguments: arguments)) }
        } else if arguments.contains(EndToEndBenchmark.flag) {
            Task { @MainActor in exit(await EndToEndBenchmark.run(arguments: arguments)) }
        } else if arguments.contains(ChatBenchmark.flag) {
            Task { @MainActor in exit(await ChatBenchmark.run(arguments: arguments)) }
        } else if arguments.contains(ToolCheck.flag) {
            Task { @MainActor in exit(await ToolCheck.run(arguments: arguments)) }
        } else if arguments.contains(MultiStepBenchmark.flag) {
            Task { @MainActor in exit(await MultiStepBenchmark.run(arguments: arguments)) }
        } else if arguments.contains(SpeakerBenchmark.flag) {
            Task { @MainActor in exit(await SpeakerBenchmark.run()) }
        }
    }

    var body: some Scene {
        MenuBarExtra {
            MenuBarContent(assistant: environment.assistant, settings: environment.settings, updates: environment.updates)
        } label: {
            Image(systemName: environment.assistant.status.symbolName)
                .accessibilityLabel(AppIdentity.name)
        }

        Window("\(AppIdentity.nameDative) hoş geldin", id: WindowID.onboarding) {
            OnboardingView(environment: environment)
        }
        .windowResizability(.contentSize)
        .defaultLaunchBehavior(environment.needsOnboarding ? .presented : .suppressed)

        Settings {
            SettingsView(environment: environment)
        }

        Window("Ses Laboratuvarı", id: WindowID.audioLab) {
            AudioLabView(model: environment.audioLab)
        }
        .windowResizability(.contentSize)
    }
}

enum WindowID {
    static let audioLab = "audio-lab"
    static let onboarding = "onboarding"
}

/// Owns the long-lived services; one instance per app run.
@MainActor
@Observable
final class AppEnvironment {
    let settings: AssistantSettings
    let speech: SpeechOutput
    let timers: TimerService
    let brain: AssistantBrain
    let memory: MemoryStore
    let routines: RoutineStore
    let commands: CustomCommandStore
    let home: HomeAssistantConfig
    let downloads: ModelDownloads
    let speakerGate: SpeakerGate
    let assistant: AssistantController
    let audioLab: AudioLabModel
    let shortcut: ListeningShortcut
    let updates: UpdateChecker
    private let hud: HUDPresenter
    private let alerts: ProactiveAlerts
    private let earthquakeAlerts: EarthquakeAlertMonitor
    private let routineScheduler: RoutineScheduler
    private let isBenchmark = CommandLine.arguments.contains(where: { $0.hasPrefix("--bench") })

    var needsOnboarding: Bool { !isBenchmark && !settings.onboardingCompleted }

    init() {
        let settings = AssistantSettings()
        let speech = SpeechOutput(voice: settings.voice, speed: settings.speechSpeed, language: settings.language)
        if let speaker = settings.outputDeviceUID { AudioDevices.selectOutput(speaker, speech: speech) }
        let announcer = Announcer()
        let timers = TimerService(fileURL: isBenchmark ? nil : TimerService.defaultFileURL()) { await announcer.target?.announce($0) }
        let memory = MemoryStore()
        let routines = RoutineStore()
        let commands = CustomCommandStore()
        let home = HomeAssistantConfig()
        let registry = ToolRegistry(catalog: AppCatalog(), timers: timers, memory: memory, routines: routines,
                                    commands: commands, home: home, language: settings.language)
        let whisper = WhisperProvider(language: settings.language)
        let meetings = MeetingRecorder()
        let brain = AssistantBrain(tools: registry.makeTools(), context: registry.context, memory: memory,
                                   spreadsheet: registry.spreadsheet, dictation: registry.dictation, meetings: meetings,
                                   whisper: whisper, language: settings.language)
        let assistant = AssistantController(settings: settings, speech: speech, handler: brain, whisper: whisper,
                                            recorder: meetings)
        announcer.target = assistant
        brain.confirmer = assistant
        assistant.onAttentionChange = { StreamPlayer.shared.setDucked($0) }
        self.settings = settings
        self.speech = speech
        self.timers = timers
        self.brain = brain
        self.memory = memory
        self.routines = routines
        self.commands = commands
        self.home = home
        let downloads = ModelDownloads()
        downloads.onDownloaded = { _ in brain.localModelDownloaded() }
        self.downloads = downloads
        speakerGate = SpeakerGate(store: VoiceprintStore(), settings: settings)
        assistant.speakerGate = speakerGate
        self.assistant = assistant
        audioLab = AudioLabModel(speech: speech)
        shortcut = ListeningShortcut(pressed: { [weak assistant] in assistant?.shortcutPressed() }, failed: {
            [weak assistant, weak settings] in
            guard let settings, !settings.wakeWordEnabled else { return }
            settings.wakeWordEnabled = true
            assistant?.restartIfRunning()
        })
        updates = UpdateChecker(settings: settings)
        hud = HUDPresenter(assistant: assistant, settings: settings)
        alerts = ProactiveAlerts(settings: settings, isListening: { [weak assistant] in assistant?.isRunning ?? false },
                                 announce: { await announcer.target?.announce($0) })
        earthquakeAlerts = EarthquakeAlertMonitor(settings: settings, announce: { await announcer.target?.announce($0) })
        routineScheduler = RoutineScheduler(store: routines, isListening: { [weak assistant] in assistant?.isRunning ?? false },
                                            run: { routine in
            if await announcer.target?.runRoutine(routine.command) != true {
                Log.brain.info("A routine was skipped: the assistant stayed busy or stopped listening")
            }
        })
        guard !isBenchmark else { return }
        shortcut.apply(settings.listeningShortcut)
        updates.start()
        hud.start()
        alerts.start()
        earthquakeAlerts.start()
        routineScheduler.start()
        speakerGate.prepare()
        brain.setLocalModelKeepAlive(settings.localModelKeepAlive)
        brain.useLocalModel(settings.localModel)
        NotificationCenter.default.addObserver(forName: NSApplication.willTerminateNotification, object: nil, queue: .main) { _ in
            MainActor.assumeIsolated { brain.shutDownLocalModel() }
        }
        NotificationCenter.default.addObserver(forName: .apiKeyChanged, object: nil, queue: .main) { note in
            guard let change = note.object as? APIKeyChange else { return }
            MainActor.assumeIsolated {
                Self.apply(change, settings: settings, brain: brain, assistant: assistant)
            }
        }
        brain.prewarm()
        if settings.onboardingCompleted, settings.listenOnLaunch { assistant.start() }
    }
}

extension AppEnvironment {
    /// One key serves a company's conversation models and its speech recognition, whichever settings tab changed it:
    /// both pick up a new key, and neither keeps using a deleted one.
    fileprivate static func apply(_ change: APIKeyChange, settings: AssistantSettings, brain: AssistantBrain,
                                  assistant: AssistantController) {
        if let model = settings.localModel, model.server.api?.keyAccount == change.account {
            if change.removed {
                settings.localModelID = nil
                brain.useLocalModel(nil)
            } else {
                brain.reconnectLocalModel()
            }
        }
        if settings.recognizer.cloudService?.service.keyAccount == change.account {
            assistant.recognizerKeyChanged()
        }
    }
}

/// Breaks the init-order cycle between services that announce and the controller that speaks.
@MainActor
private final class Announcer {
    weak var target: AssistantController?
}
