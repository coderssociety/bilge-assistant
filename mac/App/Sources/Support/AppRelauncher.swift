import AppKit

/// Quits and starts a fresh copy, so menus load in a newly chosen language, or a newer version put in its place.
enum AppRelauncher {
    /// Once this process has exited, `staged` takes the app's place and is started. If the swap fails the old app is
    /// put back and started instead, so Bilge is never left missing.
    @MainActor
    static func replace(with staged: URL) {
        let script = "while /bin/kill -0 \(ProcessInfo.processInfo.processIdentifier) 2>/dev/null; do /bin/sleep 0.2; done; "
            + "app=$1; new=$2; old=\"$app.old-update\"; /bin/rm -rf \"$old\"; "
            + "if /bin/mv \"$app\" \"$old\"; then "
            + "if /bin/mv \"$new\" \"$app\"; then /bin/rm -rf \"$old\"; else /bin/mv \"$old\" \"$app\"; /bin/rm -rf \"$new\"; fi; "
            + "else /bin/rm -rf \"$new\"; fi; /usr/bin/open \"$app\""
        let process = Process()
        process.executableURL = URL(filePath: "/bin/sh")
        // The paths are passed as arguments, never put into the script text.
        process.arguments = ["-c", script, "replace", Bundle.main.bundlePath, staged.path]
        do {
            try process.run()
        } catch {
            Log.app.error("Could not schedule the update: \(error.localizedDescription, privacy: .public)")
            try? FileManager.default.removeItem(at: staged)
            return
        }
        NSApp.terminate(nil)
    }

    @MainActor
    static func relaunch(arguments: [String] = []) {
        let process = Process()
        process.executableURL = URL(filePath: "/bin/sh")
        // Waits for this process to exit, then opens the app again; the path is passed as an argument.
        process.arguments = [
            "-c", "while /bin/kill -0 \(ProcessInfo.processInfo.processIdentifier) 2>/dev/null; do /bin/sleep 0.2; done; "
                + "path=$1; shift; /usr/bin/open \"$path\" --args \"$@\"",
            "relaunch", Bundle.main.bundlePath,
        ] + arguments
        do {
            try process.run()
        } catch {
            Log.app.error("Could not schedule relaunch: \(error.localizedDescription, privacy: .public)")
            return
        }
        NSApp.terminate(nil)
    }
}
