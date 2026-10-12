import AsistanCore
import SwiftUI

@main
struct AsistanApp: App {
    @State private var audioLab = AudioLabModel(speech: SpeechOutput())

    var body: some Scene {
        MenuBarExtra(AppIdentity.name, systemImage: "waveform.circle") {
            MenuContent()
        }

        Window("Ses Laboratuvarı", id: WindowID.audioLab) {
            AudioLabView(model: audioLab)
        }
        .windowResizability(.contentSize)
    }
}

enum WindowID {
    static let audioLab = "audio-lab"
}

private struct MenuContent: View {
    @Environment(\.openWindow) private var openWindow

    var body: some View {
        Button("Ses Laboratuvarı…") {
            openWindow(id: WindowID.audioLab)
            NSApplication.shared.activate()
        }
        Divider()
        Button("Çıkış") { NSApplication.shared.terminate(nil) }
            .keyboardShortcut("q")
    }
}
