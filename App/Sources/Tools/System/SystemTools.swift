import AppKit
import FoundationModels

struct VolumeTool: AssistantTool {
    let name = "setVolume"
    let description = "Mac'in ses seviyesini ayarlar, artırır, azaltır, sessize alır ya da sesi açar."
    private static let step = 10

    @Generable
    enum Action {
        case set, increase, decrease, mute, unmute
    }

    @Generable
    struct Arguments {
        var action: Action
        @Guide(description: "Sadece 'set' için hedef seviye", .range(0...100))
        var level: Int?
    }

    func call(arguments: Arguments) async throws -> String {
        let currentLevel = "(output volume of (get volume settings))"
        do {
            switch arguments.action {
            case .set:
                guard let level = arguments.level else {
                    return ToolReply.failure(String(localized: "Hedef seviye belirtilmedi."))
                }
                return try await apply("\(level)")
            case .increase:
                return try await apply("\(currentLevel) + \(Self.step)")
            case .decrease:
                return try await apply("\(currentLevel) - \(Self.step)")
            case .mute:
                _ = try await AppleScriptRunner.run("set volume with output muted")
                return String(localized: "Ses kapatıldı.")
            case .unmute:
                let level = try await AppleScriptRunner.run("set volume without output muted\nreturn \(currentLevel)")
                return String(localized: "Ses açıldı, seviye yüzde \(level).")
            }
        } catch {
            return ToolReply.failure(error)
        }
    }

    /// Reads, clamps and sets in one script, since every script starts an osascript process.
    private func apply(_ levelExpression: String) async throws -> String {
        let level = try await AppleScriptRunner.run("""
        set target to \(levelExpression)
        if target > 100 then set target to 100
        if target < 0 then set target to 0
        set volume without output muted
        set volume output volume target
        return target
        """)
        return String(localized: "Ses seviyesi yüzde \(level).")
    }
}

struct MediaTool: AssistantTool {
    let name = "controlMusic"
    let description = "Spotify veya Müzik uygulamasında çalmayı başlatır, duraklatır, sonraki/önceki şarkıya geçer ya da çalan şarkıyı söyler."

    @Generable
    enum Action {
        case play, pause, toggle, next, previous, nowPlaying
    }

    @Generable
    struct Arguments {
        var action: Action
    }

    func call(arguments: Arguments) async throws -> String {
        let running = await MainActor.run { Self.runningPlayer() }
        // Telling a closed Music to pause opens it first, and the command then times out.
        guard let player = running ?? (arguments.action == .play ? "Music" : nil) else {
            return String(localized: "Şu an çalan bir şey yok.")
        }
        let command: String
        switch arguments.action {
        case .play: command = "play"
        case .pause: command = "pause"
        case .toggle: command = "playpause"
        case .next: command = "next track"
        case .previous: command = "previous track"
        case .nowPlaying:
            command = "if player state is playing then return (name of current track) & \" - \" & (artist of current track)\nreturn \"\""
        }
        do {
            let output = try await AppleScriptRunner.run("tell application \(AppleScriptRunner.quoted(player))\n\(command)\nend tell")
            switch arguments.action {
            case .nowPlaying:
                return output.isEmpty ? String(localized: "Şu an çalan bir şey yok.") : String(localized: "Çalan: \(output).")
            case .play: return String(localized: "\(player) çalıyor.")
            case .pause: return String(localized: "\(player) duraklatıldı.")
            case .toggle: return String(localized: "\(player) oynat/duraklat yapıldı.")
            case .next: return String(localized: "Sonraki şarkıya geçildi.")
            case .previous: return String(localized: "Önceki şarkıya dönüldü.")
            }
        } catch {
            return ToolReply.failure(error)
        }
    }

    @MainActor
    private static func runningPlayer() -> String? {
        let running = Set(NSWorkspace.shared.runningApplications.compactMap(\.bundleIdentifier))
        if running.contains("com.spotify.client") { return "Spotify" }
        return running.contains("com.apple.Music") ? "Music" : nil
    }
}

struct SystemActionTool: AssistantTool {
    let name = "systemAction"
    let description = "Yalnızca şunları yapar: ekranı kilitlemek, Mac'i uyutmak, karanlık/aydınlık görünüme geçmek. Odak ve rahatsız etme modları bu araçla yapılmaz."

    @Generable
    enum Action {
        case lockScreen, sleep, darkModeOn, darkModeOff, toggleDarkMode
    }

    @Generable
    struct Arguments {
        var action: Action
    }

    func call(arguments: Arguments) async throws -> String {
        do {
            switch arguments.action {
            case .lockScreen:
                _ = try await ProcessRunner.run("/usr/bin/pmset", ["displaysleepnow"])
                return String(localized: "Ekran kapatıldı.")
            case .sleep:
                _ = try await ProcessRunner.run("/usr/bin/pmset", ["sleepnow"])
                return String(localized: "Mac uyku moduna alınıyor.")
            case .darkModeOn, .darkModeOff, .toggleDarkMode:
                let value = switch arguments.action {
                case .darkModeOn: "true"
                case .darkModeOff: "false"
                default: "not dark mode"
                }
                let enabled = try await AppleScriptRunner.run("""
                tell application "System Events" to tell appearance preferences
                set dark mode to \(value)
                return dark mode
                end tell
                """)
                return enabled == "true"
                    ? String(localized: "Karanlık mod açık.")
                    : String(localized: "Karanlık mod kapalı.")
            }
        } catch {
            return ToolReply.failure(error)
        }
    }
}
