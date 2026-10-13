import SwiftUI

struct ModelSettingsView: View {
    @Bindable var settings: AssistantSettings
    let brain: AssistantBrain
    @State private var models: [LMStudioClient.Model] = []
    @State private var listError: String?
    @State private var isWorking = false

    private let client = LMStudioClient()

    var body: some View {
        Form {
            Section("Komutlar") {
                if let reason = brain.unavailableReason {
                    Label(reason, systemImage: "exclamationmark.triangle").foregroundStyle(.orange)
                } else {
                    Label("Apple cihaz içi model hazır.", systemImage: "checkmark.shield").foregroundStyle(.green)
                }
                Text("Komutları anlamak ve Mac'te iş yapmak için her zaman bu model kullanılır: hızlıdır ve testlerimizde komutların hepsini doğru yönlendirdi.")
                    .font(.caption).foregroundStyle(.secondary)
            }

            Section("Sohbet ve ekran yanıtları") {
                Picker("Model", selection: $settings.localModelID) {
                    Text("Apple cihaz içi model").tag(String?.none)
                    ForEach(models) { model in
                        Text(model.label).tag(Optional(model.id))
                    }
                    if let id = settings.localModelID, !models.contains(where: { $0.id == id }) {
                        Text(id).tag(Optional(id))
                    }
                }
                serverStatus
                Text("Genel bilgi sorularında, sohbette ve ekran özetlerinde LM Studio'daki büyük model daha bilgili. 20 zor soruluk testimizde Apple modeli 17, Qwen 4-bit 19, Qwen 8-bit 20 soruyu bildi. 4-bit daha hızlıdır (ilk kelime yaklaşık 1 sn); 8-bit biraz daha doğru ama yarı hızda.")
                    .font(.caption).foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
                Text("Model LM Studio'da açık kaldıkça bellekte durur (4-bit yaklaşık 15 GB, 8-bit 28 GB). LM Studio'ya ulaşılamazsa o yanıt Apple modeliyle verilir. Her şey yine Mac'inde kalır.")
                    .font(.caption).foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .formStyle(.grouped)
        .task { await refresh(startingServer: false) }
        .onChange(of: settings.localModelID) { _, id in brain.useLocalModel(id) }
    }

    @ViewBuilder
    private var serverStatus: some View {
        if !LMStudioClient.isInstalled {
            Label("LM Studio kurulu değil.", systemImage: "info.circle").foregroundStyle(.secondary)
        } else if let listError {
            HStack {
                Label(listError, systemImage: "exclamationmark.triangle").foregroundStyle(.orange)
                Spacer()
                Button("LM Studio'yu başlat") { Task { await refresh(startingServer: true) } }
                    .disabled(isWorking)
            }
        } else if let selected = models.first(where: { $0.id == settings.localModelID }) {
            Label(selected.isLoaded ? "Model yüklü ve hazır." : "Model ilk soruda yüklenecek (15–30 sn).",
                  systemImage: selected.isLoaded ? "checkmark.circle" : "clock")
                .foregroundStyle(selected.isLoaded ? .green : .secondary)
        }
    }

    private func refresh(startingServer: Bool) async {
        guard LMStudioClient.isInstalled else { return }
        isWorking = true
        defer { isWorking = false }
        do {
            if startingServer { try await client.startServerIfNeeded() }
            models = try await client.chatModels()
            listError = nil
        } catch {
            listError = "LM Studio sunucusu kapalı."
        }
    }
}

private extension LMStudioClient.Model {
    var label: String {
        [id, quantization].compactMap { $0 }.joined(separator: " · ")
    }
}
