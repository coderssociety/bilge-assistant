import SwiftUI

/// The Home Assistant server smart-home commands go to: its address and a long-lived access token, kept in the Keychain.
struct SmartHomeSettingsView: View {
    @Bindable var home: HomeAssistantConfig
    @State private var tokenDraft = ""
    @State private var testing = false
    @State private var outcome: Outcome?

    private enum Outcome {
        case connected
        case failed(String)
    }

    var body: some View {
        Form {
            Section("Home Assistant") {
                LabeledContent("Adres") {
                    TextField("", text: $home.address, prompt: Text(verbatim: "http://homeassistant.local:8123"))
                        .textContentType(.URL)
                        .frame(maxWidth: 260)
                }
                if !home.address.isEmpty, home.baseURL == nil {
                    Text("Adres http:// ya da https:// ile başlamalı, ör. http://192.168.1.20:8123.")
                        .font(.caption).foregroundStyle(.red)
                }
                LabeledContent("Erişim anahtarı") {
                    HStack {
                        SecureField("", text: $tokenDraft, prompt: home.hasToken ? Text("Kayıtlı") : Text("Uzun ömürlü erişim anahtarı"))
                            .frame(maxWidth: 260)
                            .onSubmit(saveToken)
                        Button("Kaydet", action: saveToken)
                            .disabled(tokenDraft.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                        if home.hasToken {
                            Button("Sil", role: .destructive, action: removeToken)
                        }
                    }
                }
                Text("Home Assistant'ta Profil > Güvenlik > Uzun ömürlü erişim anahtarları bölümünden oluştur. Anahtar Anahtar Zinciri'nde saklanır ve yalnızca bu adrese gönderilir.")
                    .font(.caption).foregroundStyle(.secondary)
                HStack {
                    Button("Bağlantıyı dene", action: test)
                        .disabled(testing || !home.isConfigured)
                    if testing { ProgressView().controlSize(.small) }
                    outcomeText
                }
            }

            Section("Kullanım") {
                Text("Ayarlandığında “salonun ışığını aç”, “klimayı 22 dereceye ayarla”, “kapı kilitli mi” gibi ev cihazı ya da oda adı geçen komutlar Home Assistant'a gönderilir ve yanıtı okunur. Kilit, garaj kapısı ve alarm değişiklikleri önce onayını ister.")
                    .font(.caption).foregroundStyle(.secondary)
            }
        }
        .formStyle(.grouped)
        .onChange(of: home.address) { outcome = nil }
    }

    @ViewBuilder
    private var outcomeText: some View {
        switch outcome {
        case nil:
            EmptyView()
        case .connected?:
            Text("Bağlandı.").font(.caption).foregroundStyle(.green)
        case let .failed(message)?:
            Text(message).font(.caption).foregroundStyle(.red)
        }
    }

    private func saveToken() {
        do {
            try home.saveToken(tokenDraft)
            tokenDraft = ""
            outcome = nil
        } catch {
            outcome = .failed(error.localizedDescription)
        }
    }

    private func removeToken() {
        do {
            try home.removeToken()
            outcome = nil
        } catch {
            outcome = .failed(error.localizedDescription)
        }
    }

    private func test() {
        testing = true
        outcome = nil
        Task {
            do {
                try await HomeAssistantClient.check(try home.connection())
                outcome = .connected
            } catch {
                outcome = .failed(error.localizedDescription)
            }
            testing = false
        }
    }
}
