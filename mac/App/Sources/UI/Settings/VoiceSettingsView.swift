import AsistanCore
import FluidAudio
import SwiftUI

struct VoiceSettingsView: View {
    @Bindable var settings: AssistantSettings
    let speech: SpeechOutput
    let assistant: AssistantController
    @State private var microphones: [AudioDevices.Device] = []
    @State private var speakers: [AudioDevices.Device] = []
    @State private var isPreviewing = false
    @State private var previewError: String?

    private var sample: String {
        String(localized: "Merhaba, ben \(AppIdentity.name). Saat 14:30'da toplantın var, hatırlatmamı ister misin?")
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
            Section("Aygıtlar") {
                devicePicker("Mikrofon", selection: $settings.inputDeviceUID, devices: microphones)
                LabeledContent("Seviye") {
                    if assistant.isRunning {
                        ProgressView(value: Double(assistant.microphoneLevel))
                            .animation(.easeOut(duration: 0.1), value: assistant.microphoneLevel)
                            .accessibilityLabel("Mikrofon seviyesi")
                    } else {
                        Text("Dinleme açıkken görünür").font(.caption).foregroundStyle(.secondary)
                    }
                }
                devicePicker("Hoparlör", selection: $settings.outputDeviceUID, devices: speakers)
                Button("Aygıtları yenile", action: refreshDevices)
            }
            Section {
                Text("Ses tamamen Mac'inde, Supertonic-3 modeliyle üretilir.")
                    .font(.caption).foregroundStyle(.secondary)
            }
        }
        .formStyle(.grouped)
        .onAppear(perform: refreshDevices)
        .onChange(of: settings.inputDeviceUID) { assistant.restartIfRunning() }
        .onChange(of: settings.outputDeviceUID) { _, uid in AudioDevices.selectOutput(uid, speech: speech) }
        .onChange(of: settings.speechSpeed) { _, speed in speech.speed = speed }
        .onChange(of: settings.voice) { _, voice in
            Task { try? await speech.setVoice(voice) }
        }
    }

    /// A chosen device that is unplugged stays listed, so the choice is not lost; the system default plays meanwhile.
    private func devicePicker(_ title: LocalizedStringKey, selection: Binding<String?>, devices: [AudioDevices.Device]) -> some View {
        Picker(title, selection: selection) {
            Text("Sistem varsayılanı").tag(String?.none)
            ForEach(devices) { Text($0.name).tag(Optional($0.uid)) }
            if let chosen = selection.wrappedValue, !devices.contains(where: { $0.uid == chosen }) {
                Text("Bağlı değil").tag(Optional(chosen))
            }
        }
    }

    private func refreshDevices() {
        microphones = AudioDevices.list(.input)
        speakers = AudioDevices.list(.output)
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
        let number = String(rawValue.dropFirst())
        return rawValue.hasPrefix("F") ? String(localized: "Kadın \(number)") : String(localized: "Erkek \(number)")
    }
}
