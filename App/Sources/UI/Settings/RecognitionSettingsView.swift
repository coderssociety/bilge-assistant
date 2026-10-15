import AsistanCore
import SwiftUI

struct RecognitionSettingsView: View {
    @Bindable var settings: AssistantSettings
    let assistant: AssistantController
    let speakerGate: SpeakerGate
    @State private var enrolling = false
    @State private var wasListening = false

    var body: some View {
        Form {
            Section("Konuşma tanıma motoru") {
                Picker("Motor", selection: $settings.recognizer) {
                    ForEach(RecognizerEngine.allCases, id: \.self) { engine in
                        Text(engine.displayName).tag(engine)
                    }
                }
                .pickerStyle(.radioGroup)
                Text(settings.recognizer.explanation(for: settings.language))
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            Section {
                Text("Her iki motor da tamamen Mac'inde çalışır; ses kaydı saklanmaz.")
                    .font(.caption).foregroundStyle(.secondary)
            }
            Section("Ses kimliği") {
                if let stored = speakerGate.store.stored {
                    Toggle("Yalnızca benim sesime yanıt ver", isOn: $settings.speakerCheckEnabled)
                    Text("Sesin \(stored.created.formatted(date: .abbreviated, time: .omitted)) tarihinde kaydedildi. Televizyon ya da odadaki başkaları komut veremez ve onay veremez; “\(AppIdentity.name), dur” herkese açıktır.")
                        .font(.caption).foregroundStyle(.secondary)
                    HStack {
                        Button("Sesimi yeniden tanıt…") { startEnrollment() }
                        Button("Ses kaydını sil", role: .destructive) {
                            try? speakerGate.store.delete()
                            settings.speakerCheckEnabled = false
                        }
                    }
                } else {
                    Text("Sesini tanıtırsan \(AppIdentity.name) yalnızca sana yanıt verir. Beş kısa cümle okuman yeterli.")
                        .font(.caption).foregroundStyle(.secondary)
                    Button("Sesimi tanıt…") { startEnrollment() }
                }
            }
        }
        .formStyle(.grouped)
        .sheet(isPresented: $enrolling, onDismiss: {
            if wasListening { assistant.start() }
        }) {
            VoiceEnrollmentView(enrollment: VoiceEnrollment(gate: speakerGate, settings: settings))
        }
        .onChange(of: settings.recognizer) { assistant.restartIfRunning() }
    }

    /// The microphone is needed for the recordings, so listening pauses until the sheet closes.
    private func startEnrollment() {
        wasListening = assistant.isRunning
        assistant.stop()
        enrolling = true
    }
}

private extension RecognizerEngine {
    func explanation(for language: AssistantLanguage) -> String {
        switch (self, language) {
        case (.appleDictation, .turkish):
            String(localized: "Önerilen. Sistemle gelir, indirme gerektirmez. Türkçe testlerimizde en doğru ve en hızlı sonucu verdi (hata oranı %2, 0,06 sn).")
        case (.whisper, .turkish):
            String(localized: "OpenAI Whisper'ın Mac'e uyarlanmış sürümü. İlk seçimde yaklaşık 1,5 GB indirilir ve hazırlanması birkaç dakika sürer. Testlerimizde daha yavaş ve daha az doğruydu (%6, 0,35 sn); aksanlı konuşmada denemeye değer.")
        case (.whisper, .english):
            String(localized: "Önerilen. İlk seçimde yaklaşık 1,5 GB indirilir. İngilizce testlerimizde Türkçe söylenen “\(AppIdentity.name)” adını 20 denemenin 17'sinde doğru duydu (0,35 sn).")
        case (.appleDictation, .english):
            String(localized: "Sistemle gelir ve çok hızlıdır, ama İngilizce testlerimizde “\(AppIdentity.name)” adını neredeyse hiç tanımadı (“Bill”, “Build” diye duydu). Uyandırma kelimesini İngilizce bir kelimeyle değiştirirsen deneyebilirsin.")
        }
    }
}
