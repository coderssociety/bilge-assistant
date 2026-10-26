import AsistanCore
import SwiftUI

struct ModelSettingsView: View {
    @Bindable var settings: AssistantSettings
    let brain: AssistantBrain
    let downloads: ModelDownloads
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
                ModelChoiceList(settings: settings, downloads: downloads, brain: brain)
            }

            if LMStudioClient.isInstalled || VMLXServer.isInstalled {
                Section("Başka programla çalışan modeller") {
                    externalModels
                }
            }

            if let model = settings.localModel, model.server.api == nil {
                Section("Bellek") {
                    Picker("Model", selection: $settings.localModelKeepAlive) {
                        ForEach(LocalModelKeepAlive.allCases, id: \.self) { Text($0.displayName).tag($0) }
                    }
                    Text(settings.localModelKeepAlive.explanation)
                        .font(.caption).foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                    Text("Model açılamazsa o yanıt Apple modeliyle verilir. Her şey Mac'inde kalır.")
                        .font(.caption).foregroundStyle(.secondary)
                }
            }
        }
        .formStyle(.grouped)
        .task { await refresh(startingLMStudio: false) }
        .onChange(of: settings.localModelID) { brain.useLocalModel(settings.localModel) }
        .onChange(of: settings.localModelKeepAlive) { brain.setLocalModelKeepAlive(settings.localModelKeepAlive) }
    }

    /// LM Studio and vMLX models, for people who already run one of them.
    @ViewBuilder
    private var externalModels: some View {
        Picker("Model", selection: externalSelection) {
            Text("Seçili değil").tag(String?.none)
            ForEach(lmStudioModels) { model in
                Text(model.label).tag(Optional(LocalModelChoice(server: .lmStudio, modelID: model.id).storageKey))
            }
            ForEach(vmlxModels, id: \.self) { id in
                Text("\(id.split(separator: "/").last ?? Substring(id)) · vMLX")
                    .tag(Optional(LocalModelChoice(server: .vmlx, modelID: id).storageKey))
            }
            if let key = externalSelection.wrappedValue, !isListed(key) {
                Text(key).tag(Optional(key))
            }
        }
        status
        Text("Bilge yalnızca kendi yüklediği modeli kapatır; LM Studio'da ya da vMLX'te senin açtığın modele dokunmaz.")
            .font(.caption).foregroundStyle(.secondary)
            .fixedSize(horizontal: false, vertical: true)
    }

    /// The LM Studio or vMLX model in use, if any; clearing it goes back to Apple's model.
    private var externalSelection: Binding<String?> {
        Binding {
            isServedByOtherProgram ? settings.localModelID : nil
        } set: { key in
            if key != nil || isServedByOtherProgram { settings.localModelID = key }
        }
    }

    private var isServedByOtherProgram: Bool {
        settings.localModel?.server == .lmStudio || settings.localModel?.server == .vmlx
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
        default:
            EmptyView()
        }
    }

    private func readiness(_ isLoaded: Bool) -> some View {
        Label(isLoaded ? "Model şu an açık." : "Model kapalı; “\(AppIdentity.name)” dediğinde açılır.",
              systemImage: isLoaded ? "checkmark.circle" : "clock")
            .foregroundStyle(isLoaded ? .green : .secondary)
    }

    private func isListed(_ key: String) -> Bool {
        guard let choice = LocalModelChoice(storageKey: key) else { return false }
        return switch choice.server {
        case .lmStudio: lmStudioModels.contains { $0.id == choice.modelID }
        case .vmlx: vmlxModels.contains(choice.modelID)
        default: true
        }
    }

    private func refresh(startingLMStudio: Bool) async {
        isWorking = true
        defer { isWorking = false }
        vmlxRunning = await VMLXServer.awakeModels()
        let served = (try? await VMLXServer.runningModels()) ?? []
        vmlxModels = VMLXServer.isInstalled ? Array(Set(VMLXServer.installedModels() + served)).sorted() : []
        guard LMStudioClient.isInstalled else { return }
        do {
            if startingLMStudio { try await lmStudio.startServerIfNeeded() }
            lmStudioModels = try await lmStudio.chatModels()
            lmStudioError = nil
        } catch {
            lmStudioError = String(localized: "LM Studio sunucusu kapalı.")
        }
    }
}

private extension LMStudioClient.Model {
    var label: String {
        [id, quantization].compactMap { $0 }.joined(separator: " · ")
    }
}

private extension LocalModelKeepAlive {
    var explanation: String {
        switch self {
        case .untilConversationEnds:
            String(localized: "“\(AppIdentity.name)” dediğinde yüklenmeye başlar, sen konuşurken büyük ölçüde hazır olur (Qwen ~4 sn, Gemma ~6 sn). Yanıt bitip devam sorusu gelmezse bellekten çıkar. Gecikirse “Bir saniye” der.")
        case .fiveMinutes, .thirtyMinutes:
            String(localized: "Arka arkaya konuşmalarda yeniden yüklemeyi bekletmez; süre dolunca bellekten çıkar.")
        case .always:
            String(localized: "Uygulama açılınca yüklenir ve kapanana kadar bellekte kalır. En hızlı yanıt, en çok bellek.")
        }
    }
}
