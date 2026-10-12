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
        Divider()
        Button(assistant.isRunning ? "Dinlemeyi kapat" : "Dinlemeyi aç") { assistant.toggle() }
            .keyboardShortcut("l")
        if assistant.status == .speaking || assistant.status == .thinking {
            Button("Yanıtı durdur") { assistant.interrupt() }
        }
        Divider()
        Button("Ses Laboratuvarı…") {
            openWindow(id: WindowID.audioLab)
            NSApplication.shared.activate()
        }
        Divider()
        Button("Çıkış") { NSApplication.shared.terminate(nil) }
            .keyboardShortcut("q")
    }
}

extension AssistantController.Status {
    var title: String {
        switch self {
        case .off: "Kapalı"
        case let .loading(message): message
        case .listening: "Dinliyor — “\(AppIdentity.name)” de"
        case .awake: "Seni dinliyorum…"
        case .transcribing: "Anlıyorum…"
        case .thinking: "Düşünüyor…"
        case .speaking: "Konuşuyor…"
        case let .failed(message): "Hata: \(message)"
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
        case .failed: "exclamationmark.circle"
        }
    }
}
