import AsistanCore
import SwiftUI

struct MenuBarContent: View {
    let assistant: AssistantController
    let settings: AssistantSettings
    let updates: UpdateChecker
    @Environment(\.openWindow) private var openWindow

    var body: some View {
        Text(assistant.statusTitle)
        if let heard = assistant.lastHeard {
            Text("Duyulan: \(heard)").lineLimit(2)
        }
        if let reply = assistant.lastReply, !reply.isEmpty {
            Text("Yanıt: \(reply)").lineLimit(3)
        }
        if let question = assistant.pendingConfirmation {
            Divider()
            Text(question).lineLimit(3)
            Button("Evet, yap") { assistant.resolveConfirmation(.confirmed) }
            Button("Hayır") { assistant.resolveConfirmation(.rejected) }
        }
        Divider()
        Button(assistant.isRunning ? "Dinlemeyi kapat" : "Dinlemeyi aç") { assistant.toggle() }
            .keyboardShortcut("l")
        if assistant.status == .speaking || assistant.status == .thinking {
            Button("Yanıtı durdur") { assistant.interrupt() }
        }
        if assistant.status == .recording {
            Button("Kaydı bitir") { assistant.finishRecording() }
        }
        Divider()
        SettingsLink { Text("Ayarlar…") }
            .keyboardShortcut(",")
        if let release = updates.available {
            switch updates.installer.state {
            case let .working(step):
                Text("\(AppIdentity.name) \(release.version): \(step)")
            case .idle, .failed:
                if updates.canInstall {
                    Button("Güncelle ve yeniden başlat: \(AppIdentity.name) \(release.version)") {
                        Task { await updates.installer.install(release) }
                    }
                }
                Button(updates.canInstall ? "Neler yeni?" : "Yeni sürüm: \(AppIdentity.name) \(release.version)…") {
                    NSWorkspace.shared.open(release.page)
                }
            }
            if case let .failed(message) = updates.installer.state {
                Text("Güncellenemedi: \(message)")
            }
        }
        Button("Kurulum rehberi…") { show(WindowID.onboarding) }
        Button("Ses Laboratuvarı…") { show(WindowID.audioLab) }
        Divider()
        Button("Çıkış") { NSApplication.shared.terminate(nil) }
            .keyboardShortcut("q")
    }

    private func show(_ id: String) {
        openWindow(id: id)
        NSApplication.shared.activate()
    }
}

extension AssistantController.Status {
    var title: String {
        switch self {
        case .off: String(localized: "Kapalı")
        case let .loading(message): message
        case .listening: String(localized: "Dinliyor — “\(AppIdentity.name)” de")
        case .awake: String(localized: "Seni dinliyorum…")
        case .transcribing: String(localized: "Anlıyorum…")
        case .thinking: String(localized: "Düşünüyor…")
        case .speaking: String(localized: "Konuşuyor…")
        case .confirming: String(localized: "Onayını bekliyorum — evet ya da hayır de")
        case .recording: String(localized: "Toplantı kaydediliyor — bitirmek için “kaydı bitir” de")
        case let .failed(message): String(localized: "Hata: \(message)")
        }
    }

    var symbolName: String {
        switch self {
        case .off: "waveform.circle"
        case .loading: "arrow.down.circle"
        case .listening: "waveform.circle.fill"
        case .awake, .transcribing: "ear.fill"
        case .thinking: "ellipsis.circle.fill"
        case .speaking: "speaker.wave.2.circle.fill"
        case .confirming: "questionmark.circle.fill"
        case .recording: "record.circle.fill"
        case .failed: "exclamationmark.circle"
        }
    }
}
