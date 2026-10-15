import AsistanCore
import SwiftUI

/// First-run setup: what the assistant is, permissions, model preparation, conversation model, voice, first command.
struct OnboardingView: View {
    enum Step: Int, CaseIterable {
        case language, welcome, permissions, preparation, model, voice, finish
    }

    let environment: AppEnvironment
    @Environment(\.dismissWindow) private var dismissWindow
    @State private var step = Step.language

    var body: some View {
        VStack(spacing: 0) {
            Group {
                switch step {
                case .language: LanguageStep(settings: environment.settings)
                case .welcome: WelcomeStep()
                case .permissions: PermissionsStep()
                case .preparation: PreparationStep(assistant: environment.assistant, brain: environment.brain)
                case .model: ModelStep(environment: environment)
                case .voice: VoiceSettingsView(settings: environment.settings, speech: environment.speech)
                case .finish: FinishStep(settings: environment.settings)
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
            .padding(24)

            Divider()
            HStack {
                StepDots(current: step)
                Spacer()
                if step != .language {
                    Button("Geri") { move(by: -1) }
                }
                Button(step == .finish ? "Dinlemeye başla" : "Devam", action: advance)
                    .buttonStyle(.borderedProminent)
                    .keyboardShortcut(.defaultAction)
                    .disabled(!canAdvance)
            }
            .padding(16)
        }
        .frame(width: 600, height: 560)
    }

    private var canAdvance: Bool {
        switch step {
        case .permissions: Permission.allCases.filter(\.isRequired).allSatisfy { $0.state == .granted }
        case .preparation: environment.assistant.status == .off && environment.brain.unavailableReason == nil
        default: true
        }
    }

    private func advance() {
        guard step == .finish else { return move(by: 1) }
        environment.settings.onboardingCompleted = true
        environment.assistant.start()
        dismissWindow(id: WindowID.onboarding)
    }

    private func move(by offset: Int) {
        step = Step(rawValue: step.rawValue + offset) ?? step
    }
}

private struct LanguageStep: View {
    let settings: AssistantSettings

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Image(systemName: "globe").font(.system(size: 44)).foregroundStyle(.tint)
            Text("Dil · Language").font(.largeTitle.bold())
            LanguageChoice(settings: settings)
        }
    }
}

private struct WelcomeStep: View {
    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Image(nsImage: NSApplication.shared.applicationIconImage).resizable().frame(width: 72, height: 72)
            Text("Merhaba, ben \(AppIdentity.name)").font(.largeTitle.bold())
            Text("Mac'inde sesle iş yaptırabileceğin Türkçe asistanın.").font(.title3).foregroundStyle(.secondary)
            VStack(alignment: .leading, spacing: 10) {
                Label("Tamamen yerel: sesin ve komutların Mac'inden dışarı çıkmaz.", systemImage: "lock.shield")
                Label("“\(AppIdentity.name)” dediğinde uyanır, öncesini dinlemez ve kaydetmez.", systemImage: "ear")
                Label("Silme, ekleme gibi önemli işlerde önce sesli onay ister.", systemImage: "checkmark.seal")
            }
            .padding(.top, 8)
        }
    }
}

private struct PermissionsStep: View {
    private static let refreshInterval = Duration.seconds(1)
    @State private var refreshToken = 0

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("İzinler").font(.title.bold())
            Text("Yıldızlı olanlar zorunlu; diğerlerini istersen sonra da verebilirsin.").foregroundStyle(.secondary)
            Form {
                ForEach(Permission.allCases.filter { $0 != .automation }) { permission in
                    PermissionRow(permission: permission, refreshToken: refreshToken) { refreshToken += 1 }
                }
            }
            .formStyle(.grouped)
        }
        .task {
            while !Task.isCancelled {
                try? await Task.sleep(for: Self.refreshInterval)
                refreshToken += 1
            }
        }
    }
}

private struct PreparationStep: View {
    let assistant: AssistantController
    let brain: AssistantBrain
    @State private var error: String?
    @State private var isDone = false

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text("Hazırlık").font(.title.bold())
            Text("Ses algılama, konuşma tanıma ve Türkçe ses modelleri hazırlanıyor. İlk seferde birkaç dakika sürebilir.")
                .foregroundStyle(.secondary)
            if let reason = brain.unavailableReason {
                Label(reason, systemImage: "exclamationmark.triangle").foregroundStyle(.orange)
            }
            if let error {
                Label(error, systemImage: "xmark.octagon").foregroundStyle(.red)
                Button("Tekrar dene") { Task { await prepare() } }
            } else if isDone {
                Label("Her şey hazır.", systemImage: "checkmark.circle.fill").foregroundStyle(.green)
            } else {
                HStack(spacing: 10) {
                    ProgressView().controlSize(.small)
                    Text(assistant.status.title)
                }
            }
        }
        .task { await prepare() }
    }

    private func prepare() async {
        error = nil
        isDone = false
        do {
            try await assistant.prepareModels()
            brain.prewarm()
            isDone = true
        } catch {
            self.error = error.localizedDescription
        }
    }
}

private struct ModelStep: View {
    let environment: AppEnvironment

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Sohbet modeli").font(.title.bold())
            Text("Komutları her zaman Apple'ın cihaz içi modeli anlar. Sohbet, genel sorular ve ekran özetleri için istersen daha bilgili bir model indirebilirsin; Bilge onu kendi içinde çalıştırır, başka program gerekmez. Sonra Ayarlar > Model'den değiştirebilirsin.")
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
            ScrollView {
                ModelChoiceList(settings: environment.settings, downloads: environment.downloads, brain: environment.brain)
                    .padding(.trailing, 8)
            }
        }
    }
}

private struct FinishStep: View {
    @Bindable var settings: AssistantSettings

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text("Hazırsın").font(.title.bold())
            Text("Şunları dene:").foregroundStyle(.secondary)
            VStack(alignment: .leading, spacing: 6) {
                ForEach([String(localized: "saat kaç?"), String(localized: "sesi yüzde otuz yap"),
                         String(localized: "Safari'yi aç"), String(localized: "on dakikalık zamanlayıcı kur"),
                         String(localized: "bugün takvimde ne var?")], id: \.self) { example in
                    Text("“\(AppIdentity.name), \(example)”").font(.body.monospaced())
                }
            }
            Text("Yanıttan sonraki birkaç saniye içinde uyandırma kelimesi olmadan devam edebilirsin.")
                .font(.callout).foregroundStyle(.secondary)
            Toggle("Uygulama her açıldığında dinlemeye başla", isOn: $settings.listenOnLaunch)
                .padding(.top, 8)
        }
    }
}

private struct StepDots: View {
    let current: OnboardingView.Step

    var body: some View {
        HStack(spacing: 6) {
            ForEach(OnboardingView.Step.allCases, id: \.self) { step in
                Circle()
                    .fill(step == current ? Color.accentColor : Color.secondary.opacity(0.3))
                    .frame(width: 7, height: 7)
            }
        }
        .accessibilityElement()
        .accessibilityLabel("Adım \(current.rawValue + 1) / \(OnboardingView.Step.allCases.count)")
    }
}
