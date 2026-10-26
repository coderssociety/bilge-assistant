import AsistanCore
import SwiftUI

extension Notification.Name {
    /// Posted with an `APIKeyChange`; the app environment updates whatever uses that key.
    static let apiKeyChanged = Notification.Name("apiKeyChanged")
}

struct APIKeyChange: Sendable {
    let account: String
    let removed: Bool
}

/// Enters or removes a service's API key. The key goes straight to the Keychain and is never shown again; one key per
/// company serves both its conversation models and its speech recognition.
struct APIKeyField: View {
    let api: ModelAPI
    @Binding var hasKey: Bool
    var onSaved: () -> Void = {}
    var onDeleted: () -> Void = {}
    @State private var keyText = ""
    @State private var problem: String?

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack {
                SecureField(hasKey ? "Yeni API anahtarı" : "API anahtarı", text: $keyText)
                    .textFieldStyle(.roundedBorder)
                    .onSubmit(save)
                Button("Kaydet", action: save)
                    .disabled(keyText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                if hasKey { Button("Anahtarı sil", role: .destructive, action: delete) }
            }
            Label(hasKey ? "\(api.name) anahtarı Anahtar Zinciri'nde kayıtlı." : "\(api.name) anahtarı kayıtlı değil.",
                  systemImage: hasKey ? "key.fill" : "key")
                .font(.caption).foregroundStyle(.secondary)
            if let problem {
                Label(problem, systemImage: "exclamationmark.triangle").font(.caption).foregroundStyle(.orange)
            }
        }
        .onAppear(perform: refresh)
        .onChange(of: api) { refresh() }
    }

    private func refresh() {
        hasKey = Keychain.contains(api.keyAccount)
        keyText = ""
        problem = nil
    }

    private func save() {
        let key = keyText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !key.isEmpty else { return }
        do {
            try Keychain.save(key, for: api.keyAccount)
            keyText = ""
            problem = nil
            hasKey = true
            NotificationCenter.default.post(name: .apiKeyChanged, object: APIKeyChange(account: api.keyAccount, removed: false))
            onSaved()
        } catch {
            problem = error.localizedDescription
        }
    }

    private func delete() {
        do {
            try Keychain.delete(api.keyAccount)
            problem = nil
            hasKey = false
            NotificationCenter.default.post(name: .apiKeyChanged, object: APIKeyChange(account: api.keyAccount, removed: true))
            onDeleted()
        } catch {
            problem = error.localizedDescription
        }
    }
}
