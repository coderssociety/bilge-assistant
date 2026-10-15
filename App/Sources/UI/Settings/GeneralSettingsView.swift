import AsistanCore
import SwiftUI

struct GeneralSettingsView: View {
    @Bindable var settings: AssistantSettings
    let assistant: AssistantController
    @State private var wakePhraseDraft = ""
    @State private var wakePhraseError: String?
    @State private var launchAtLogin = LoginItem.isEnabled
    @State private var loginItemError: String?

    private static let maxWakeWords = 3
    private static let minWakeCharacters = 3

    var body: some View {
        Form {
            Section("Dil · Language") {
                LanguageChoice(settings: settings)
            }

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

            Section("Hatırlatmalar") {
                Toggle("Yaklaşan toplantıları ve vakti gelen anımsatıcıları sesli söyle", isOn: $settings.proactiveAlertsEnabled)
                Picker("Toplantıdan önce", selection: $settings.eventAlertLeadMinutes) {
                    ForEach(AssistantSettings.eventAlertLeadChoices, id: \.self) { Text("\($0) dakika").tag($0) }
                }
                .disabled(!settings.proactiveAlertsEnabled)
                Toggle("Günün ilk “günaydın”ında günün özetini söyle", isOn: $settings.morningBriefingEnabled)
                Text("Yalnızca dinleme açıkken ve Takvim/Anımsatıcılar izni verilmişse çalışır.")
                    .font(.caption).foregroundStyle(.secondary)
            }

            Section("Hava durumu") {
                LabeledContent("Şehir") {
                    TextField("", text: $settings.weatherCity, prompt: Text(WeatherTool.fallbackCity))
                        .frame(maxWidth: 200)
                }
                Text("Şehir söylemediğinde hava durumu bu şehir için verilir. Şehir adı Open-Meteo'ya gönderilir.")
                    .font(.caption).foregroundStyle(.secondary)
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
            wakePhraseError = String(localized: "En az \(Self.minWakeCharacters) harf ve en fazla \(Self.maxWakeWords) kelime olmalı.")
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
            loginItemError = String(localized: "Giriş öğesi ayarlanamadı: \(error.localizedDescription)")
            launchAtLogin = LoginItem.isEnabled
        }
    }
}
