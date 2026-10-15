import AsistanCore
import SwiftUI

struct MenuBarContent: View {
    let assistant: AssistantController
    let settings: AssistantSettings
    @Environment(\.openWindow) private var openWindow

    var body: some View {
        Text(assistant.status.title)
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
        Divider()
        SettingsLink { Text("Ayarlar…") }
            .keyboardShortcut(",")
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
        case .failed: "exclamationmark.circle"
        }
    }
}
