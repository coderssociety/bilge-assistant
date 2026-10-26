import AsistanCore
import SwiftUI

/// A conversation model behind an API: a hosted service with the user's key (kept in the Keychain), or Ollama or
/// llama.cpp on this Mac. Not a tap-to-select card like the others, since it holds text fields.
struct APIModelCard: View {
    @Bindable var settings: AssistantSettings
    let use: (LocalModelChoice?) -> Void
    @State private var server = LocalModelChoice.Server.openAI
    @State private var hasKey = false
    @State private var modelID = ""
    @State private var models: [String] = []
    @State private var status: Status?
    @State private var isWorking = false

    private enum Status {
        case info(String)
        case problem(String)
    }

    private var api: ModelAPI? { server.api }
    private var selected: LocalModelChoice? { settings.localModel.flatMap { $0.server.api == nil ? nil : $0 } }
    private var trimmedModelID: String { modelID.trimmingCharacters(in: .whitespacesAndNewlines) }

    var body: some View {
        HStack(alignment: .top, spacing: 10) {
            Image(systemName: selected != nil ? "largecircle.fill.circle" : "circle")
                .foregroundStyle(selected != nil ? Color.accentColor : .secondary)
                .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: 8) {
                Text("API ile bağlanan model").font(.headline)
                Text("OpenAI, Anthropic, Google Gemini, OpenRouter, Groq ve DeepSeek senin API anahtarınla; Ollama ve llama.cpp Mac'inde çalışan sunucudan.")
                    .font(.caption).foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
                Picker("Servis", selection: $server) {
                    ForEach(ModelAPI.all, id: \.server) { Text($0.name).tag($0.server) }
                }
                if let api {
                    if api.isHosted {
                        APIKeyField(api: api, hasKey: $hasKey, onSaved: { keySaved(api) }, onDeleted: { keyDeleted(api) })
                    }
                    modelRow(api)
                    statusLine
                    footnote(api)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .padding(10)
        .background(selected != nil ? Color.accentColor.opacity(0.08) : .clear, in: .rect(cornerRadius: 8))
        .overlay(RoundedRectangle(cornerRadius: 8).strokeBorder(selected != nil ? Color.accentColor : .secondary.opacity(0.3)))
        .onAppear {
            if let selected { server = selected.server }
            serviceChanged()
        }
        .onChange(of: server) { serviceChanged() }
    }

    private func modelRow(_ api: ModelAPI) -> some View {
        HStack {
            TextField("Model", text: $modelID, prompt: Text("ör. \(Self.exampleModel(api))"))
                .textFieldStyle(.roundedBorder)
            if !models.isEmpty {
                Menu("Listeden seç") {
                    ForEach(models, id: \.self) { id in Button(id) { modelID = id } }
                }
                .fixedSize()
            }
            Button("Modelleri getir") { fetchModels(api) }
                .disabled(isWorking || (api.isHosted && !hasKey))
            Button("Kullan") { use(LocalModelChoice(server: api.server, modelID: trimmedModelID)) }
                .disabled(trimmedModelID.isEmpty || (api.isHosted && !hasKey) || selected?.storageKey == currentKey(api))
        }
    }

    @ViewBuilder
    private var statusLine: some View {
        if let selected, let selectedAPI = selected.server.api {
            Label("Kullanılıyor: \(selectedAPI.name) · \(selected.modelID)", systemImage: "checkmark.circle")
                .font(.caption).foregroundStyle(.green)
        }
        switch status {
        case let .info(text): Label(text, systemImage: "info.circle").font(.caption).foregroundStyle(.secondary)
        case let .problem(text): Label(text, systemImage: "exclamationmark.triangle").font(.caption).foregroundStyle(.orange)
        case nil: EmptyView()
        }
    }

    private func footnote(_ api: ModelAPI) -> some View {
        Text(api.isHosted
            ? String(localized: "Sohbet ve bilgi soruların, Bilge'nin onlar için okuduğu metinlerle (ekran, belge, web sayfası, e-posta) birlikte \(api.name) servisine gider ve ücreti anahtarının hesabına yazılır. Komutları anlamak ve Mac'te iş yapmak yine Apple'ın cihaz içi modelinde kalır. Servis yanıt vermezse o cevabı Apple modeli verir.")
            : String(localized: "\(api.name) bu Mac'te çalışmalı; Bilge yalnızca 127.0.0.1 adresine bağlanır ve hiçbir şey Mac'inden çıkmaz."))
            .font(.caption).foregroundStyle(.secondary)
            .fixedSize(horizontal: false, vertical: true)
    }

    private func currentKey(_ api: ModelAPI) -> String {
        LocalModelChoice(server: api.server, modelID: trimmedModelID).storageKey
    }

    private func serviceChanged() {
        guard let api else { return }
        hasKey = Keychain.contains(api.keyAccount)
        models = []
        status = nil
        modelID = selected?.server == server ? selected?.modelID ?? "" : ""
    }

    /// The app environment reconnects or drops the selected model itself (`APIKeyChange`); this only updates the card.
    private func keySaved(_ api: ModelAPI) {
        fetchModels(api)
    }

    private func keyDeleted(_ api: ModelAPI) {
        models = []
        status = nil
    }

    /// Also checks the key: a service that lists its models has accepted it.
    private func fetchModels(_ api: ModelAPI) {
        isWorking = true
        status = .info(String(localized: "Bağlanıyor…"))
        Task {
            defer { isWorking = false }
            do {
                let found = try await APIModelEndpoint.models(of: api, apiKey: try APIModelEndpoint.key(for: api))
                guard api.server == server else { return }
                models = found
                status = .info(found.isEmpty
                    ? String(localized: "Bağlantı tamam ama listelenen model yok; model adını kendin yaz.")
                    : String(localized: "Bağlantı tamam: \(found.count) model bulundu."))
            } catch let error as URLError where !api.isHosted && error.code == .cannotConnectToHost {
                status = .problem(String(localized: "\(api.name) sunucusuna ulaşılamadı; Mac'inde çalışıyor mu?"))
            } catch {
                status = .problem(error.localizedDescription)
            }
        }
    }

    private static func exampleModel(_ api: ModelAPI) -> String {
        switch api.server {
        case .openAI: "gpt-5-mini"
        case .anthropic: "claude-haiku-4-5"
        case .gemini: "gemini-2.5-flash"
        case .openRouter: "anthropic/claude-sonnet-4.5"
        case .groq: "llama-3.3-70b-versatile"
        case .deepSeek: "deepseek-chat"
        case .ollama: "qwen3:8b"
        default: "model"
        }
    }
}
