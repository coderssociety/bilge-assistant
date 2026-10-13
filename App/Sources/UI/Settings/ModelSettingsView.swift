import AsistanCore
import SwiftUI

struct ModelSettingsView: View {
    @Bindable var settings: AssistantSettings
    let brain: AssistantBrain
    @State private var lmStudioModels: [LMStudioClient.Model] = []
    @State private var lmStudioError: String?
    @State private var vmlxModels: [String] = []
    @State private var vmlxRunning: [String] = []
    @State private var isWorking = false

    private let lmStudio = LMStudioClient()

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
                    ForEach(lmStudioModels) { model in
                        Text(model.label).tag(Optional(LocalModelChoice(server: .lmStudio, modelID: model.id).storageKey))
                    }
                    ForEach(vmlxModels, id: \.self) { id in
                        Text("\(id.split(separator: "/").last ?? Substring(id)) · vMLX")
                            .tag(Optional(LocalModelChoice(server: .vmlx, modelID: id).storageKey))
                    }
                    if let key = settings.localModelID, !isListed(key) {
                        Text(key).tag(Optional(key))
                    }
                }
                status
                Text("Genel bilgi sorularında, sohbette ve ekran özetlerinde büyük yerel modeller daha bilgili. 20 zor soruluk testimizde Apple modeli 14, Qwen 4-bit 19, Gemma 4 31B 19 soruyu bildi. Qwen daha hızlı üretir; Gemma ilk kelimeye daha çabuk başlar.")
                    .font(.caption).foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
                Text("Seçilen model açık kaldıkça bellekte durur (Qwen 4-bit ~16 GB, Gemma ~23 GB). Bilge'nin yüklediği modeli başka modele geçince ya da Bilge kapanınca boşaltır. Model hazır değilse o yanıt Apple modeliyle verilir. Her şey Mac'inde kalır.")
                    .font(.caption).foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .formStyle(.grouped)
        .task { await refresh(startingLMStudio: false) }
        .onChange(of: settings.localModelID) { brain.useLocalModel(settings.localModel) }
    }

    @ViewBuilder
    private var status: some View {
        switch settings.localModel?.server {
        case .lmStudio:
            if let lmStudioError {
                HStack {
                    Label(lmStudioError, systemImage: "exclamationmark.triangle").foregroundStyle(.orange)
                    Spacer()
                    Button("LM Studio'yu başlat") { Task { await refresh(startingLMStudio: true) } }
                        .disabled(isWorking)
                }
            } else if let selected = lmStudioModels.first(where: { $0.id == settings.localModel?.modelID }) {
                readiness(selected.isLoaded)
            }
        case .vmlx:
            readiness(vmlxRunning.contains(settings.localModel?.modelID ?? ""))
        case nil:
            EmptyView()
        }
    }

    private func readiness(_ isLoaded: Bool) -> some View {
        Label(isLoaded ? "Model yüklü ve hazır." : "Model arka planda yükleniyor ya da ilk soruda yüklenecek (15–30 sn).",
              systemImage: isLoaded ? "checkmark.circle" : "clock")
            .foregroundStyle(isLoaded ? .green : .secondary)
    }

    private func isListed(_ key: String) -> Bool {
        guard let choice = LocalModelChoice(storageKey: key) else { return false }
        return switch choice.server {
        case .lmStudio: lmStudioModels.contains { $0.id == choice.modelID }
        case .vmlx: vmlxModels.contains(choice.modelID)
        }
    }

    private func refresh(startingLMStudio: Bool) async {
        isWorking = true
        defer { isWorking = false }
        vmlxRunning = (try? await VMLXServer.runningModels()) ?? []
        vmlxModels = VMLXServer.isInstalled ? Array(Set(VMLXServer.installedModels() + vmlxRunning)).sorted() : []
        guard LMStudioClient.isInstalled else { return }
        do {
            if startingLMStudio { try await lmStudio.startServerIfNeeded() }
            lmStudioModels = try await lmStudio.chatModels()
            lmStudioError = nil
        } catch {
            lmStudioError = "LM Studio sunucusu kapalı."
        }
    }
}

private extension LMStudioClient.Model {
    var label: String {
        [id, quantization].compactMap { $0 }.joined(separator: " · ")
    }
}
