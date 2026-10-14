import AppKit

/// Quits and starts a fresh copy, so menus load in a newly chosen language.
enum AppRelauncher {
    @MainActor
    static func relaunch() {
        let process = Process()
        process.executableURL = URL(filePath: "/bin/sh")
        // Waits for this process to exit, then opens the app again; the path is passed as an argument.
        process.arguments = [
            "-c", "while /bin/kill -0 \(ProcessInfo.processInfo.processIdentifier) 2>/dev/null; do /bin/sleep 0.2; done; /usr/bin/open \"$1\"",
            "relaunch", Bundle.main.bundlePath,
        ]
        do {
            try process.run()
        } catch {
            Log.app.error("Could not schedule relaunch: \(error.localizedDescription, privacy: .public)")
            return
        }
        NSApp.terminate(nil)
    }
}
