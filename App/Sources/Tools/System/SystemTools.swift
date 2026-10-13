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
        do {
            return try await MainActor.run {
                let current = Int(try AppleScriptRunner.run("output volume of (get volume settings)")) ?? 50
                switch arguments.action {
                case .set:
                    guard let level = arguments.level else { return ToolReply.failure("Hedef seviye belirtilmedi.") }
                    return try apply(level)
                case .increase:
                    return try apply(current + Self.step)
                case .decrease:
                    return try apply(current - Self.step)
                case .mute:
                    _ = try AppleScriptRunner.run("set volume with output muted")
                    return "Ses kapatıldı."
                case .unmute:
                    _ = try AppleScriptRunner.run("set volume without output muted")
                    return "Ses açıldı, seviye yüzde \(current)."
                }
            }
        } catch {
            return ToolReply.failure(error)
        }
    }

    @MainActor
    private func apply(_ level: Int) throws -> String {
        let clamped = min(max(level, 0), 100)
        _ = try AppleScriptRunner.run("set volume without output muted\nset volume output volume \(clamped)")
        return "Ses seviyesi yüzde \(clamped)."
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
        let player = await MainActor.run { Self.activePlayer() }
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
            let output = try await MainActor.run {
                try AppleScriptRunner.run("tell application \(AppleScriptRunner.quoted(player))\n\(command)\nend tell")
            }
            switch arguments.action {
            case .nowPlaying: return output.isEmpty ? "Şu an çalan bir şey yok." : "Çalan: \(output)."
            case .play: return "\(player) çalıyor."
            case .pause: return "\(player) duraklatıldı."
            case .toggle: return "\(player) oynat/duraklat yapıldı."
            case .next: return "Sonraki şarkıya geçildi."
            case .previous: return "Önceki şarkıya dönüldü."
            }
        } catch {
            return ToolReply.failure(error)
        }
    }

    @MainActor
    private static func activePlayer() -> String {
        let running = Set(NSWorkspace.shared.runningApplications.compactMap(\.bundleIdentifier))
        return running.contains("com.spotify.client") ? "Spotify" : "Music"
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
                return "Ekran kapatıldı."
            case .sleep:
                _ = try await ProcessRunner.run("/usr/bin/pmset", ["sleepnow"])
                return "Mac uyku moduna alınıyor."
            case .darkModeOn, .darkModeOff, .toggleDarkMode:
                let value = switch arguments.action {
                case .darkModeOn: "true"
                case .darkModeOff: "false"
                default: "not dark mode"
                }
                let enabled = try await MainActor.run {
                    try AppleScriptRunner.run("""
                    tell application "System Events" to tell appearance preferences
                    set dark mode to \(value)
                    return dark mode
                    end tell
                    """)
                }
                return enabled == "true" ? "Karanlık mod açık." : "Karanlık mod kapalı."
            }
        } catch {
            return ToolReply.failure(error)
        }
    }
}
