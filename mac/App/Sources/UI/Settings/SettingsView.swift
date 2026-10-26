import SwiftUI

struct SettingsView: View {
    let environment: AppEnvironment

    var body: some View {
        TabView {
            Tab("Genel", systemImage: "gearshape") {
                GeneralSettingsView(settings: environment.settings, assistant: environment.assistant,
                                    shortcut: environment.shortcut, updates: environment.updates)
            }
            Tab("Model", systemImage: "cpu") {
                ModelSettingsView(settings: environment.settings, brain: environment.brain, downloads: environment.downloads)
            }
            Tab("Ses", systemImage: "speaker.wave.2") {
                VoiceSettingsView(settings: environment.settings, speech: environment.speech, assistant: environment.assistant)
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
            Tab("Rutinler", systemImage: "repeat") {
                RoutinesView(store: environment.routines)
            }
            Tab("Komutlar", systemImage: "terminal") {
                CustomCommandsView(store: environment.commands)
            }
            Tab("Akıllı ev", systemImage: "house") {
                SmartHomeSettingsView(home: environment.home)
            }
            // A tab builder takes at most ten children.
            Group {
                Tab("Geçmiş", systemImage: "clock.arrow.circlepath") {
                    HistoryView()
                }
                Tab("Hakkında", systemImage: "info.circle") {
                    AboutView()
                }
            }
        }
        .frame(width: 680, height: 470)
    }
}
