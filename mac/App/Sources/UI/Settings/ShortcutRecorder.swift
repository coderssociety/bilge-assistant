import AppKit
import Carbon.HIToolbox
import SwiftUI

/// Records the listening shortcut: click, then press the keys. Escape stops recording without a change.
struct ShortcutRecorder: View {
    @Binding var combination: KeyCombination?
    /// Released while recording, so pressing the current combination records it instead of waking the assistant.
    let shortcut: ListeningShortcut
    @State private var monitor: Any?

    var body: some View {
        HStack {
            Button(label) { monitor == nil ? startRecording() : stopRecording() }
                .frame(minWidth: 140)
            if combination != nil, monitor == nil {
                Button("Temizle") { combination = nil }
            }
        }
        .onDisappear(perform: stopRecording)
        .onReceive(NotificationCenter.default.publisher(for: NSWindow.didResignKeyNotification)) { _ in stopRecording() }
    }

    private var label: String {
        if monitor != nil { return String(localized: "Tuşlara bas…") }
        return combination?.display ?? String(localized: "Kısayol yok")
    }

    private func startRecording() {
        shortcut.apply(nil)
        // A local monitor sees only keys pressed in this app's own windows; no permission is involved.
        monitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { event in
            MainActor.assumeIsolated { record(event) }
            return nil
        }
    }

    private func record(_ event: NSEvent) {
        if Int(event.keyCode) == kVK_Escape {
            stopRecording()
        } else if let recorded = KeyCombination(event: event) {
            combination = recorded
            stopRecording()
        } else {
            NSSound.beep()
        }
    }

    private func stopRecording() {
        guard let monitor else { return }
        NSEvent.removeMonitor(monitor)
        self.monitor = nil
        shortcut.apply(combination)
    }
}
