import AsistanCore
import SwiftUI

struct GeneralSettingsView: View {
    @Bindable var settings: AssistantSettings
    let assistant: AssistantController
    let brain: AssistantBrain
    @State private var wakePhraseDraft = ""
    @State private var wakePhraseError: String?
    @State private var launchAtLogin = LoginItem.isEnabled
    @State private var loginItemError: String?

    private static let maxWakeWords = 3
    private static let minWakeCharacters = 3

    var body: some View {
        Form {
            Section("Uyandırma") {
                LabeledContent("Uyandırma kelimesi") {
                    TextField("", text: $wakePhraseDraft, prompt: Text(AppIdentity.defaultWakePhrase))
                        .onSubmit(applyWakePhrase)
                        .frame(maxWidth: 200)
                }
                if let wakePhraseError {
                    Text(wakePhraseError).font(.caption).foregroundStyle(.red)
                }
                LabeledContent("Hassasiyet") {
                    HStack {
                        Text("Katı").font(.caption).foregroundStyle(.secondary)
                        Slider(value: $settings.wakeSensitivity, in: 0...1)
                        Text("Esnek").font(.caption).foregroundStyle(.secondary)
                    }
                }
                Text("Esnek ayar kelimeyi daha kolay yakalar ama başka konuşmalarda yanlışlıkla uyanma ihtimali artar.")
                    .font(.caption).foregroundStyle(.secondary)
                Toggle("Yanıttan sonra kelimesiz devam sorusu dinle", isOn: $settings.followUpEnabled)
                Toggle("Konuşurken sözünü kesebileyim (“\(AppIdentity.name), dur”)", isOn: $settings.bargeInEnabled)
                    .help("Yankı iptaliyle asistanın kendi sesini süzer. Kulaklıkla en iyi sonucu verir.")
            }

            Section("Başlangıç") {
                Toggle("Uygulama açılınca dinlemeye başla", isOn: $settings.listenOnLaunch)
                Toggle("Mac açıldığında uygulamayı başlat", isOn: $launchAtLogin)
                    .onChange(of: launchAtLogin) { _, enabled in updateLoginItem(enabled) }
                if let loginItemError {
                    Text(loginItemError).font(.caption).foregroundStyle(.red)
                }
                Toggle("Ekranda durum panelini göster", isOn: $settings.showHUD)
            }

            Section("Dil modeli") {
                if let reason = brain.unavailableReason {
                    Label(reason, systemImage: "exclamationmark.triangle").foregroundStyle(.orange)
                } else {
                    Label("Apple cihaz içi model hazır. Hiçbir şey Mac'inden dışarı çıkmaz.", systemImage: "checkmark.shield")
                        .foregroundStyle(.green)
                }
            }
        }
        .formStyle(.grouped)
        .onAppear { wakePhraseDraft = settings.wakePhrase }
        .onChange(of: settings.wakeSensitivity) { assistant.restartIfRunning() }
        .onChange(of: settings.followUpEnabled) { assistant.restartIfRunning() }
        .onChange(of: settings.bargeInEnabled) { assistant.restartIfRunning() }
    }

    private func applyWakePhrase() {
        let phrase = wakePhraseDraft.trimmingCharacters(in: .whitespacesAndNewlines)
        let words = phrase.split(separator: " ")
        guard phrase.count >= Self.minWakeCharacters, (1...Self.maxWakeWords).contains(words.count) else {
            wakePhraseError = "En az \(Self.minWakeCharacters) harf ve en fazla \(Self.maxWakeWords) kelime olmalı."
            return
        }
        wakePhraseError = nil
        guard phrase != settings.wakePhrase else { return }
        settings.wakePhrase = phrase
        assistant.restartIfRunning()
    }

    private func updateLoginItem(_ enabled: Bool) {
        do {
            try LoginItem.setEnabled(enabled)
            loginItemError = nil
        } catch {
            loginItemError = "Giriş öğesi ayarlanamadı: \(error.localizedDescription)"
            launchAtLogin = LoginItem.isEnabled
        }
    }
}
