import AsistanCore
import FluidAudio
import SwiftUI

struct VoiceSettingsView: View {
    @Bindable var settings: AssistantSettings
    let speech: SpeechOutput
    @State private var isPreviewing = false
    @State private var previewError: String?

    private var sample: String {
        "Merhaba, ben \(AppIdentity.name). Saat 14:30'da toplantın var, hatırlatmamı ister misin?"
    }

    var body: some View {
        Form {
            Section("Asistanın sesi") {
                Picker("Ses", selection: $settings.voice) {
                    ForEach(Supertonic3Voice.allCases, id: \.self) { voice in
                        Text(voice.turkishLabel).tag(voice)
                    }
                }
                LabeledContent("Konuşma hızı") {
                    HStack {
                        Slider(value: $settings.speechSpeed, in: 0.8...1.4, step: 0.05)
                        Text(settings.speechSpeed.formatted(.number.precision(.fractionLength(2))))
                            .monospacedDigit()
                            .frame(width: 40)
                    }
                }
                HStack {
                    Button(isPreviewing ? "Durdur" : "Dinle", action: togglePreview)
                    if isPreviewing { ProgressView().controlSize(.small) }
                }
                if let previewError {
                    Text(previewError).font(.caption).foregroundStyle(.red)
                }
            }
            Section {
                Text("Ses tamamen Mac'inde, Supertonic-3 modeliyle üretilir.")
                    .font(.caption).foregroundStyle(.secondary)
            }
        }
        .formStyle(.grouped)
        .onChange(of: settings.speechSpeed) { _, speed in speech.speed = speed }
        .onChange(of: settings.voice) { _, voice in
            Task { try? await speech.setVoice(voice) }
        }
    }

    private func togglePreview() {
        if isPreviewing {
            speech.stop()
            isPreviewing = false
            return
        }
        isPreviewing = true
        previewError = nil
        Task {
            defer { isPreviewing = false }
            do {
                speech.speed = settings.speechSpeed
                try await speech.setVoice(settings.voice)
                try await speech.speak(sample)
            } catch {
                previewError = error.localizedDescription
            }
        }
    }
}

extension Supertonic3Voice {
    var turkishLabel: String {
        let number = rawValue.dropFirst()
        return rawValue.hasPrefix("F") ? "Kadın \(number)" : "Erkek \(number)"
    }
}
