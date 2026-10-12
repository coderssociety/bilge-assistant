import AsistanCore
import SwiftUI

@main
struct AsistanApp: App {
    @State private var environment = AppEnvironment()

    init() {
        let arguments = CommandLine.arguments
        if arguments.contains(ASRBenchmark.flag) {
            Task { @MainActor in exit(await ASRBenchmark.run(arguments: arguments)) }
        }
    }

    var body: some Scene {
        MenuBarExtra {
            MenuBarContent(assistant: environment.assistant, settings: environment.settings)
        } label: {
            Image(systemName: environment.assistant.status.symbolName)
                .accessibilityLabel(AppIdentity.name)
        }

        Window("Ses Laboratuvarı", id: WindowID.audioLab) {
            AudioLabView(model: environment.audioLab)
        }
        .windowResizability(.contentSize)
    }
}

enum WindowID {
    static let audioLab = "audio-lab"
}

/// Owns the long-lived services; one instance per app run.
@MainActor
@Observable
final class AppEnvironment {
    let settings: AssistantSettings
    let speech: SpeechOutput
    let assistant: AssistantController
    let audioLab: AudioLabModel

    init() {
        let settings = AssistantSettings()
        let speech = SpeechOutput(voice: settings.voice, speed: settings.speechSpeed)
        self.settings = settings
        self.speech = speech
        assistant = AssistantController(settings: settings, speech: speech, handler: EchoCommandHandler())
        audioLab = AudioLabModel(speech: speech)
        let isBenchmark = CommandLine.arguments.contains(ASRBenchmark.flag)
        if settings.listenOnLaunch, !isBenchmark { assistant.start() }
    }
}
