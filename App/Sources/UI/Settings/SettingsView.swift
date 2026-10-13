import SwiftUI

struct SettingsView: View {
    let environment: AppEnvironment

    var body: some View {
        TabView {
            Tab("Genel", systemImage: "gearshape") {
                GeneralSettingsView(settings: environment.settings, assistant: environment.assistant)
            }
            Tab("Model", systemImage: "cpu") {
                ModelSettingsView(settings: environment.settings, brain: environment.brain)
            }
            Tab("Ses", systemImage: "speaker.wave.2") {
                VoiceSettingsView(settings: environment.settings, speech: environment.speech)
            }
            Tab("Tanıma", systemImage: "waveform") {
                RecognitionSettingsView(settings: environment.settings, assistant: environment.assistant)
            }
            Tab("İzinler", systemImage: "lock.shield") {
                PermissionsView()
            }
            Tab("Geçmiş", systemImage: "clock.arrow.circlepath") {
                HistoryView()
            }
        }
        .frame(width: 560, height: 470)
    }
}
