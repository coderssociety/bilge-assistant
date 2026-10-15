import AsistanCore
import SwiftUI

/// Apple's model, a downloadable one or the user's own MLX model for conversation, with what each can do.
/// Used in onboarding and settings.
struct ModelChoiceList: View {
    @Bindable var settings: AssistantSettings
    let downloads: ModelDownloads
    let brain: AssistantBrain
    @State private var customModels: [CustomModels.Model] = []
    @State private var foundModels: [CustomModels.Model] = []
    @State private var searchFolders: [URL] = []

    private let physicalMemory = ProcessInfo.processInfo.physicalMemory

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            AppleModelRow(isSelected: settings.localModelID == nil) { select(nil) }
            ForEach(ModelCatalog.models) { model in
                DownloadableModelRow(
                    model: model,
                    state: downloads.state(of: model),
                    isSelected: settings.localModelID == choice(for: model).storageKey,
                    fits: model.fits(physicalMemoryBytes: physicalMemory),
                    hasLeftovers: downloads.hasLeftovers(model),
                    select: { select(model) },
                    download: { downloads.start(model); select(model) },
                    cancel: { downloads.cancel(model) },
                    delete: { delete(model) })
            }
            LocalModelsHeader(refresh: refreshCustomModels, addFolder: addFolder)
            ForEach(customModels) { model in
                row(for: model, choice: LocalModelChoice(server: .custom, modelID: model.name))
            }
            ForEach(foundModels) { model in
                row(for: model, choice: LocalModelChoice(server: .folder, modelID: model.id))
            }
            if customModels.isEmpty, foundModels.isEmpty {
                Text("Bu Mac'te MLX modeli bulunamadı.").font(.caption).foregroundStyle(.secondary)
            }
            SearchFoldersFooter(folders: searchFolders, remove: removeFolder)
        }
        .task { refreshCustomModels() }
    }

    private func choice(for model: DownloadableModel) -> LocalModelChoice {
        LocalModelChoice(server: .builtIn, modelID: model.id)
    }

    private func row(for model: CustomModels.Model, choice: LocalModelChoice) -> some View {
        CustomModelRow(model: model, isSelected: settings.localModelID == choice.storageKey,
                       tooLarge: UInt64(max(model.bytes, 0)) > physicalMemory / 4 * 3) { use(choice) }
    }

    private func refreshCustomModels() {
        customModels = CustomModels.scan()
        foundModels = ModelLibrary.scan()
        searchFolders = ModelLibrary.userFolders
    }

    private func addFolder() {
        if ModelLibrary.addFolder() { refreshCustomModels() }
    }

    private func removeFolder(_ folder: URL) {
        ModelLibrary.removeFolder(folder)
        refreshCustomModels()
    }

    /// A model still downloading can be chosen: Apple's model answers until it is in place.
    private func select(_ model: DownloadableModel?) {
        use(model.map(choice(for:)))
    }

    private func use(_ choice: LocalModelChoice?) {
        settings.localModelID = choice?.storageKey
        brain.useLocalModel(settings.localModel)
    }

    private func delete(_ model: DownloadableModel) {
        if settings.localModelID == choice(for: model).storageKey { select(nil) }
        do {
            try downloads.delete(model)
        } catch {
            Log.brain.error("Could not delete \(model.id, privacy: .public): \(error.localizedDescription, privacy: .public)")
        }
    }
}

private struct AppleModelRow: View {
    let isSelected: Bool
    let select: () -> Void

    var body: some View {
        ChoiceCard(isSelected: isSelected, select: select) {
            VStack(alignment: .leading, spacing: 4) {
                Text("Apple cihaz içi model").font(.headline)
                Text("İndirme yok · sistemle gelir").font(.caption).foregroundStyle(.secondary)
                Label("Bütün Mac komutları: uygulamalar, takvim, anımsatıcı, müzik, dosyalar, Excel, dikte, tarayıcı, mesaj ve e-posta", systemImage: "checkmark")
                Label("Kısa sohbet, hesap, hava durumu, döviz, haberler", systemImage: "checkmark")
                Label("Genel bilgi sorularında daha sık yanılır, uzun metinleri daha kısa özetler", systemImage: "minus")
                Label("“Ahmet'in numarasını bul ve ona mesaj at” gibi birbirine bağlı işleri planlayamaz, parçaları ayrı ayrı yapar", systemImage: "minus")
            }
            .font(.callout)
            .labelStyle(CompactLabelStyle())
        }
    }
}

private struct DownloadableModelRow: View {
    let model: DownloadableModel
    let state: ModelDownloads.State
    let isSelected: Bool
    let fits: Bool
    let hasLeftovers: Bool
    let select: () -> Void
    let download: () -> Void
    let cancel: () -> Void
    let delete: () -> Void

    var body: some View {
        ChoiceCard(isSelected: isSelected, isEnabled: fits || state == .downloaded, select: primaryAction) {
            VStack(alignment: .leading, spacing: 4) {
                HStack {
                    Text(model.name).font(.headline)
                    Spacer()
                    controls
                }
                Text("\(model.downloadBytes.formatted(.byteCount(style: .file))) indirme · en az \(model.minimumMemoryGB) GB bellek · \(model.license)")
                    .font(.caption).foregroundStyle(.secondary)
                // The catalog lives in AsistanCore; its Turkish summaries are translated in the app's string catalog.
                Text(LocalizedStringKey(model.summary)).font(.callout).fixedSize(horizontal: false, vertical: true)
                status
            }
        }
    }

    private func primaryAction() {
        switch state {
        case .downloaded, .downloading: select()
        case .notDownloaded, .failed: download()
        }
    }

    @ViewBuilder
    private var controls: some View {
        switch state {
        case .notDownloaded, .failed:
            HStack {
                if hasLeftovers { Button("Yarım kalanı sil", role: .destructive, action: delete) }
                Button(hasLeftovers ? "Sürdür" : "İndir", action: download).disabled(!fits)
            }
        case .downloading:
            Button("Durdur", action: cancel)
        case .downloaded:
            Button("Sil", role: .destructive, action: delete)
        }
    }

    @ViewBuilder
    private var status: some View {
        switch state {
        case let .downloading(fraction):
            ProgressView(value: fraction) {
                Text("İniyor · %\(Int(fraction * 100)) · bitene kadar Apple modeli yanıt verir").font(.caption)
            }
        case let .failed(message):
            Label(message, systemImage: "exclamationmark.triangle").font(.caption).foregroundStyle(.orange)
        case .notDownloaded where !fits:
            Label("Bu Mac'in belleği bu model için yetmez.", systemImage: "memorychip").font(.caption).foregroundStyle(.secondary)
        case .notDownloaded where isSelected:
            Label("Seçili ama indirilmedi; şimdilik Apple modeli yanıt veriyor.", systemImage: "info.circle")
                .font(.caption).foregroundStyle(.secondary)
        case .downloaded, .notDownloaded:
            EmptyView()
        }
    }
}

private struct LocalModelsHeader: View {
    let refresh: () -> Void
    let addFolder: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack {
                Text("Bu Mac'teki modeller").font(.headline)
                Spacer()
                Button("Yenile", action: refresh)
                Button("Klasör ekle…", action: addFolder)
            }
            Text("LM Studio'nun, Hugging Face önbelleğinin ve eklediğin klasörlerin içindeki MLX modelleri. Kopyalanmaz, bulundukları yerden uygulamanın içinde çalışır; LM Studio'nun açık olması gerekmez. GGUF modeller burada görünmez. Desteklenmeyen bir model türü açılamazsa cevabı Apple modeli verir.")
                .font(.caption).foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(.top, 6)
    }
}

private struct SearchFoldersFooter: View {
    let folders: [URL]
    let remove: (URL) -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            ForEach(folders, id: \.self) { folder in
                HStack {
                    Label(folder.path(percentEncoded: false), systemImage: "folder")
                        .lineLimit(1).truncationMode(.middle)
                    Spacer()
                    Button("Kaldır") { remove(folder) }
                }
                .font(.caption)
            }
            HStack {
                Text("Bir modeli Bilge'nin kendi klasörüne de koyabilirsin.")
                Spacer()
                Button("Bilge'nin klasörünü aç") { CustomModels.revealInFinder() }
            }
            .font(.caption).foregroundStyle(.secondary)
        }
    }
}

private struct CustomModelRow: View {
    let model: CustomModels.Model
    let isSelected: Bool
    let tooLarge: Bool
    let select: () -> Void

    private var isReady: Bool {
        if case .ready = model.status { true } else { false }
    }

    var body: some View {
        ChoiceCard(isSelected: isSelected, isEnabled: isReady, select: select) {
            VStack(alignment: .leading, spacing: 4) {
                Text(model.name).font(.headline)
                switch model.status {
                case let .ready(modelType):
                    Text("\(model.bytes.formatted(.byteCount(style: .file))) · tür: \(modelType)\(model.source.map { " · \($0)" } ?? "")")
                        .font(.caption).foregroundStyle(.secondary)
                    if tooLarge {
                        Label("Bu Mac'in belleği için büyük olabilir.", systemImage: "memorychip")
                            .font(.caption).foregroundStyle(.orange)
                    }
                case let .missing(reason):
                    Label("Kullanılamıyor: \(String(localized: String.LocalizationValue(reason))).", systemImage: "exclamationmark.triangle")
                        .font(.caption).foregroundStyle(.orange)
                }
            }
        }
    }
}

private struct ChoiceCard<Content: View>: View {
    let isSelected: Bool
    var isEnabled = true
    let select: () -> Void
    @ViewBuilder let content: Content

    var body: some View {
        HStack(alignment: .top, spacing: 10) {
            Image(systemName: isSelected ? "largecircle.fill.circle" : "circle")
                .foregroundStyle(isSelected ? Color.accentColor : .secondary)
                .accessibilityHidden(true)
            content.frame(maxWidth: .infinity, alignment: .leading)
        }
        .padding(10)
        .background(isSelected ? Color.accentColor.opacity(0.08) : .clear, in: .rect(cornerRadius: 8))
        .overlay(RoundedRectangle(cornerRadius: 8).strokeBorder(isSelected ? Color.accentColor : .secondary.opacity(0.3)))
        .contentShape(.rect)
        .onTapGesture { if isEnabled { select() } }
        .opacity(isEnabled ? 1 : 0.6)
        .accessibilityElement(children: .contain)
        .accessibilityAddTraits(isSelected ? [.isButton, .isSelected] : .isButton)
    }
}

private struct CompactLabelStyle: LabelStyle {
    func makeBody(configuration: Configuration) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: 6) {
            configuration.icon.font(.caption).frame(width: 12)
            configuration.title.fixedSize(horizontal: false, vertical: true)
        }
    }
}
