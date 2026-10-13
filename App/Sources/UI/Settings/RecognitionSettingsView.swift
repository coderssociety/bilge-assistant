import SwiftUI

struct RecognitionSettingsView: View {
    @Bindable var settings: AssistantSettings
    let assistant: AssistantController

    var body: some View {
        Form {
            Section("Konuşma tanıma motoru") {
                Picker("Motor", selection: $settings.recognizer) {
                    ForEach(RecognizerEngine.allCases, id: \.self) { engine in
                        Text(engine.displayName).tag(engine)
                    }
                }
                .pickerStyle(.radioGroup)
                Text(settings.recognizer.explanation)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            Section {
                Text("Her iki motor da tamamen Mac'inde çalışır; ses kaydı saklanmaz.")
                    .font(.caption).foregroundStyle(.secondary)
            }
        }
        .formStyle(.grouped)
        .onChange(of: settings.recognizer) { assistant.restartIfRunning() }
    }
}

private extension RecognizerEngine {
    var explanation: String {
        switch self {
        case .appleDictation:
            "Önerilen. Sistemle gelir, indirme gerektirmez. Türkçe testlerimizde en doğru ve en hızlı sonucu verdi (hata oranı %2, 0,06 sn)."
        case .whisper:
            "OpenAI Whisper'ın Mac'e uyarlanmış sürümü. İlk seçimde yaklaşık 1,5 GB indirilir ve hazırlanması birkaç dakika sürer. Testlerimizde daha yavaş ve daha az doğruydu (%6, 0,35 sn); aksanlı konuşmada denemeye değer."
        }
    }
}
