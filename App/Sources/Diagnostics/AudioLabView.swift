import FluidAudio
import SwiftUI

struct AudioLabView: View {
    @Bindable var model: AudioLabModel

    var body: some View {
        Form {
            Section("Mikrofon ve konuşma algılama") {
                HStack {
                    Button(model.isListening ? "Dinlemeyi durdur" : "Dinlemeyi başlat") { model.toggleListening() }
                    Spacer()
                    Label(model.isSpeechActive ? "Konuşma var" : "Sessiz",
                          systemImage: model.isSpeechActive ? "waveform" : "waveform.slash")
                        .foregroundStyle(model.isSpeechActive ? .green : .secondary)
                }
                ProgressView(value: Double(model.speechProbability))
                    .tint(model.isSpeechActive ? .green : .accentColor)
                    .accessibilityLabel("Konuşma olasılığı")
            }

            Section("Türkçe seslendirme") {
                TextField("Söylenecek metin", text: $model.text, axis: .vertical)
                    .lineLimit(2...5)
                Picker("Ses", selection: $model.voice) {
                    ForEach(Supertonic3Voice.allCases, id: \.self) { voice in
                        Text(Self.label(for: voice)).tag(voice)
                    }
                }
                LabeledContent("Hız") {
                    Slider(value: $model.speed, in: 0.8...1.4, step: 0.05)
                    Text(model.speed.formatted(.number.precision(.fractionLength(2))))
                        .monospacedDigit()
                        .frame(width: 40)
                }
                HStack {
                    Button("Seslendir") { model.speak() }
                        .keyboardShortcut(.return, modifiers: .command)
                        .disabled(model.text.trimmingCharacters(in: .whitespaces).isEmpty)
                    Button("Durdur") { model.stopSpeaking() }
                        .disabled(!model.isSpeaking)
                    if model.isSpeaking { ProgressView().controlSize(.small) }
                }
            }

            if let status = model.statusMessage {
                Section { Text(status).foregroundStyle(.secondary) }
            }

            Section("Olaylar") {
                ForEach(model.log) { entry in
                    HStack {
                        Text(entry.date, format: .dateTime.hour().minute().second())
                            .monospacedDigit()
                            .foregroundStyle(.secondary)
                        Text(entry.message)
                    }
                }
            }
        }
        .formStyle(.grouped)
        .frame(minWidth: 460, minHeight: 520)
    }

    private static func label(for voice: Supertonic3Voice) -> String {
        let raw = voice.rawValue
        return raw.hasPrefix("F") ? "Kadın \(raw.dropFirst())" : "Erkek \(raw.dropFirst())"
    }
}
