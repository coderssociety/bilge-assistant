import AsistanCore
import SwiftUI

@main
struct AsistanApp: App {
    @State private var environment = AppEnvironment()

    init() {
        let arguments = CommandLine.arguments
        if arguments.contains(ASRBenchmark.flag) {
            Task { @MainActor in exit(await ASRBenchmark.run(arguments: arguments)) }
        } else if arguments.contains(LLMBenchmark.flag) {
            Task { @MainActor in exit(await LLMBenchmark.run(arguments: arguments)) }
        } else if arguments.contains(EndToEndBenchmark.flag) {
            Task { @MainActor in exit(await EndToEndBenchmark.run()) }
        } else if arguments.contains(ChatBenchmark.flag) {
            Task { @MainActor in exit(await ChatBenchmark.run(arguments: arguments)) }
        } else if arguments.contains(ToolCheck.flag) {
            Task { @MainActor in exit(await ToolCheck.run(arguments: arguments)) }
        } else if arguments.contains(MultiStepBenchmark.flag) {
            Task { @MainActor in exit(await MultiStepBenchmark.run(arguments: arguments)) }
        }
    }

    var body: some Scene {
        MenuBarExtra {
            MenuBarContent(assistant: environment.assistant, settings: environment.settings)
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
    let assistant: AssistantController
    let audioLab: AudioLabModel
    private let hud: HUDPresenter
    private let alerts: ProactiveAlerts
    private let isBenchmark = CommandLine.arguments.contains(where: { $0.hasPrefix("--bench") })

    var needsOnboarding: Bool { !isBenchmark && !settings.onboardingCompleted }

    init() {
        let settings = AssistantSettings()
        let speech = SpeechOutput(voice: settings.voice, speed: settings.speechSpeed)
        let announcer = Announcer()
        let timers = TimerService { await announcer.target?.announce($0) }
        let memory = MemoryStore()
        let registry = ToolRegistry(catalog: AppCatalog(), timers: timers, memory: memory)
        let brain = AssistantBrain(tools: registry.makeTools(), context: registry.context, memory: memory,
                                   spreadsheet: registry.spreadsheet)
        let assistant = AssistantController(settings: settings, speech: speech, handler: brain)
        announcer.target = assistant
        brain.confirmer = assistant
        self.settings = settings
        self.speech = speech
        self.timers = timers
        self.brain = brain
        self.memory = memory
        self.assistant = assistant
        audioLab = AudioLabModel(speech: speech)
        hud = HUDPresenter(assistant: assistant, settings: settings)
        alerts = ProactiveAlerts(settings: settings, isListening: { [weak assistant] in assistant?.isRunning ?? false },
                                 announce: { await announcer.target?.announce($0) })
        guard !isBenchmark else { return }
        hud.start()
        alerts.start()
        brain.setLocalModelKeepAlive(settings.localModelKeepAlive)
        brain.useLocalModel(settings.localModel)
        NotificationCenter.default.addObserver(forName: NSApplication.willTerminateNotification, object: nil, queue: .main) { _ in
            MainActor.assumeIsolated { brain.shutDownLocalModel() }
        }
        brain.prewarm()
        if settings.onboardingCompleted, settings.listenOnLaunch { assistant.start() }
    }
}

/// Breaks the init-order cycle between services that announce and the controller that speaks.
@MainActor
private final class Announcer {
    weak var target: AssistantController?
}
