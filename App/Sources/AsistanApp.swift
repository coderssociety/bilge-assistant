import AsistanCore
import SwiftUI

@main
struct AsistanApp: App {
    var body: some Scene {
        MenuBarExtra(AppIdentity.name, systemImage: "waveform.circle") {
            Text("\(AppIdentity.name) hazırlanıyor…")
            Divider()
            Button("Çıkış") { NSApplication.shared.terminate(nil) }
                .keyboardShortcut("q")
        }
    }
}
