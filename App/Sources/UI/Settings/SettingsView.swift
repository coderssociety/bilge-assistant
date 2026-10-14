import SwiftUI

struct SettingsView: View {
    let environment: AppEnvironment

    var body: some View {
        TabView {
            Tab("Genel", systemImage: "gearshape") {
                GeneralSettingsView(settings: environment.settings, assistant: environment.assistant)
            }
            Tab("Model", systemImage: "cpu") {
                ModelSettingsView(settings: environment.settings, brain: environment.brain, downloads: environment.downloads)
            }
            Tab("Ses", systemImage: "speaker.wave.2") {
                VoiceSettingsView(settings: environment.settings, speech: environment.speech)
            }
            Tab("Tanıma", systemImage: "waveform") {
                RecognitionSettingsView(settings: environment.settings, assistant: environment.assistant, speakerGate: environment.speakerGate)
            }
            Tab("İzinler", systemImage: "lock.shield") {
                PermissionsView()
            }
            Tab("Hafıza", systemImage: "brain") {
                MemoryView(memory: environment.memory)
            }
            Tab("Geçmiş", systemImage: "clock.arrow.circlepath") {
                HistoryView()
            }
            Tab("Hakkında", systemImage: "info.circle") {
                AboutView()
            }
        }
        .frame(width: 560, height: 470)
    }
}
