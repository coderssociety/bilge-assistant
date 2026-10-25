import AppKit
import AsistanCore
import FoundationModels
import IOKit.hidsystem

struct VolumeTool: AssistantTool {
    let name = "setVolume"
    let description = "Mac'in ses seviyesini ayarlar, artırır, azaltır, sessize alır ya da sesi açar."
    private static let step = 10
    private static let unmutedMarker = "unmuted "

    @Generable
    enum Action {
        case set, increase, decrease, mute, unmute
    }

    @Generable
    struct Arguments {
        var action: Action
        @Guide(description: "Sadece 'set' için hedef seviye", .range(0...100))
        var level: Int?
        @Guide(description: "Sadece 'increase'/'decrease' için ne kadar: 'yüzde 20 artır' → 20. Söylenmediyse boş bırak.", .range(1...100))
        var amount: Int?
    }

    func refine(_ arguments: Arguments, command: String) -> Arguments {
        guard AppLanguage.current == .turkish, let change = VolumeChange.parse(command) else { return arguments }
        return Arguments(action: change > 0 ? .increase : .decrease, level: nil, amount: abs(change))
    }

    func call(arguments: Arguments) async throws -> String {
        let currentLevel = "(output volume of (get volume settings))"
        let amount = arguments.amount ?? Self.step
        do {
            switch arguments.action {
            case .set:
                guard let level = arguments.level else {
                    return ToolReply.failure(String(localized: "Hedef seviye belirtilmedi."))
                }
                return try await apply("\(level)")
            case .increase:
                return try await apply("\(currentLevel) + \(amount)")
            case .decrease:
                return try await apply("\(currentLevel) - \(amount)")
            case .mute:
                _ = try await AppleScriptRunner.run("set volume with output muted")
                return String(localized: "Ses kapatıldı.")
            case .unmute:
                // "Sesi aç" with the sound already on means louder; unmuting alone left it as quiet as it was.
                let output = try await AppleScriptRunner.run("""
                if output muted of (get volume settings) is true then
                set volume without output muted
                return "\(Self.unmutedMarker)" & \(currentLevel)
                end if
                \(Self.setClamped("\(currentLevel) + \(Self.step)"))
                """)
                guard output.hasPrefix(Self.unmutedMarker) else { return String(localized: "Ses seviyesi yüzde \(output).") }
                return String(localized: "Ses açıldı, seviye yüzde \(String(output.dropFirst(Self.unmutedMarker.count))).")
            }
        } catch {
            return ToolReply.failure(error)
        }
    }

    /// Reads, clamps and sets in one script, since every script starts an osascript process.
    private func apply(_ levelExpression: String) async throws -> String {
        let level = try await AppleScriptRunner.run(Self.setClamped(levelExpression))
        return String(localized: "Ses seviyesi yüzde \(level).")
    }

    private static func setClamped(_ levelExpression: String) -> String {
        """
        set target to \(levelExpression)
        if target > 100 then set target to 100
        if target < 0 then set target to 0
        set volume without output muted
        set volume output volume target
        return target
        """
    }
}

struct MediaTool: AssistantTool {
    let name = "controlMusic"
    let description = "Müziği ya da tarayıcıdaki videoyu oynatır, duraklatır, sonrakine/öncekine geçer; Müzik ve Spotify'da ileri/geri sarar, baştan başlatır, karıştırmayı ve tekrarı açıp kapatır, çalanı söyler."
    private static let defaultSeekSeconds = 15

    @Generable
    enum Action {
        case play, pause, toggle, next, previous, nowPlaying, seekForward, seekBackward, restartTrack
        case shuffleOn, shuffleOff, repeatOn, repeatOff
    }

    @Generable
    struct Arguments {
        var action: Action
        @Guide(description: "Sadece seekForward/seekBackward için saniye: '30 saniye ileri sar' → 30, '1 dakika geri sar' → 60. Söylenmediyse boş bırak.", .range(1...3600))
        var seconds: Int?
    }

    func refine(_ arguments: Arguments, command: String) -> Arguments {
        guard [.seekForward, .seekBackward].contains(arguments.action) else { return arguments }
        let said = MacControlRequest.seekSeconds(command, language: AppLanguage.current)
        return Arguments(action: arguments.action, seconds: said ?? arguments.seconds)
    }

    func call(arguments: Arguments) async throws -> String {
        do {
            switch arguments.action {
            case .play, .pause, .toggle, .next, .previous: return try await transport(arguments.action)
            case .nowPlaying: return try await nowPlaying()
            default: return try await playerOnly(arguments)
            }
        } catch {
            return ToolReply.failure(error)
        }
    }

    /// The app that is playing gets AppleScript; with neither playing, the media keys reach whatever
    /// plays elsewhere (a browser, a podcast app), as the keyboard's own keys would.
    private func transport(_ action: Action) async throws -> String {
        let open = await MainActor.run { MusicPlayers.running() }
        let states = try await MusicPlayers.states(of: open)
        guard let app = MusicPlayerChoice.forTransport(states, resuming: action == .play) else {
            return try await pressMediaKey(action)
        }
        let command = switch action {
        case .play: "play"
        case .pause: "pause"
        case .next: "next track"
        case .previous: "previous track"
        default: "playpause"
        }
        _ = try await AppleScriptRunner.run("tell application \(AppleScriptRunner.quoted(app.rawValue))\n\(command)\nend tell")
        let player = MusicPlayers.displayName(app)
        return switch action {
        case .play: String(localized: "\(player) çalıyor.")
        case .pause: String(localized: "\(player) duraklatıldı.")
        case .next: String(localized: "Sonraki şarkıya geçildi.")
        case .previous: String(localized: "Önceki şarkıya dönüldü.")
        default: String(localized: "\(player) oynat/duraklat yapıldı.")
        }
    }

    private func pressMediaKey(_ action: Action) async throws -> String {
        let key = switch action {
        case .next: NX_KEYTYPE_FAST
        case .previous: NX_KEYTYPE_REWIND
        default: NX_KEYTYPE_PLAY
        }
        try await MainActor.run { try SystemKeys.press(key) }
        return switch action {
        case .play: String(localized: "Oynatılıyor.")
        case .pause: String(localized: "Duraklatıldı.")
        case .next: String(localized: "Sonrakine geçildi.")
        case .previous: String(localized: "Öncekine dönüldü.")
        default: String(localized: "Oynat/duraklat yapıldı.")
        }
    }

    /// Telling a closed Music anything opens it first, and the command then times out.
    private func nowPlaying() async throws -> String {
        guard let app = try await MusicPlayers.controlTarget() else { return String(localized: "Şu an çalan bir şey yok.") }
        let output = try await AppleScriptRunner.run("""
        tell application \(AppleScriptRunner.quoted(app.rawValue))
        if player state is stopped then return ""
        set stateName to "paused"
        if player state is playing then set stateName to "playing"
        return stateName & linefeed & (name of current track) & " - " & (artist of current track)
        end tell
        """)
        return Self.nowPlayingReply(output)
    }

    /// Seeking, shuffle and repeat need the player's own scripting; Music and Spotify name them differently.
    private func playerOnly(_ arguments: Arguments) async throws -> String {
        guard let app = try await MusicPlayers.controlTarget() else {
            return ToolReply.failure(String(localized: "Bunu yalnızca Müzik ve Spotify'da yapabiliyorum, ikisi de açık değil."))
        }
        let isMusic = app == .music
        let seconds = arguments.seconds ?? Self.defaultSeekSeconds
        let (command, reply): (String, String) = switch arguments.action {
        case .seekForward:
            ("set player position to (player position) + \(seconds)",
             String(localized: "\(Duration.seconds(seconds).spoken) ileri sardım."))
        case .seekBackward:
            ("""
            set target to (player position) - \(seconds)
            if target < 0 then set target to 0
            set player position to target
            """, String(localized: "\(Duration.seconds(seconds).spoken) geri sardım."))
        case .restartTrack: ("set player position to 0\nplay", String(localized: "Şarkı baştan başladı."))
        case .shuffleOn: (isMusic ? "set shuffle enabled to true" : "set shuffling to true", String(localized: "Karışık çalma açık."))
        case .shuffleOff: (isMusic ? "set shuffle enabled to false" : "set shuffling to false", String(localized: "Karışık çalma kapalı."))
        case .repeatOn: (isMusic ? "set song repeat to all" : "set repeating to true", String(localized: "Tekrar açık."))
        default: (isMusic ? "set song repeat to off" : "set repeating to false", String(localized: "Tekrar kapalı."))
        }
        _ = try await AppleScriptRunner.run("tell application \(AppleScriptRunner.quoted(app.rawValue))\n\(command)\nend tell")
        return reply
    }

    private static func nowPlayingReply(_ output: String) -> String {
        let lines = output.split(separator: "\n", maxSplits: 1).map(String.init)
        guard lines.count == 2 else { return String(localized: "Şu an çalan bir şey yok.") }
        return lines[0] == "playing"
            ? String(localized: "Çalan: \(lines[1]).")
            : String(localized: "Duraklatılmış şarkı: \(lines[1]).")
    }
}

struct SystemActionTool: AssistantTool {
    let name = "systemAction"
    let description = "Ekranı kilitler ya da kapatır, Mac'i uyutur, yeniden başlatır, kapatır, oturumu kapatır, karanlık/aydınlık görünüme geçer, Rahatsız Etme/odak modunu açar ya da kapatır."
    private static let loginFramework = "/System/Library/PrivateFrameworks/login.framework/Versions/Current/login"

    @Generable
    enum Action {
        case lockScreen, screenOff, sleep, darkModeOn, darkModeOff, toggleDarkMode, focusOn, focusOff, restart, shutDown, logOut
    }

    @Generable
    struct Arguments {
        @Guide(description: "lockScreen kilitler (açmak için parola ister); screenOff yalnızca ekranı kapatır/karartır; sleep Mac'i uyutur; shutDown Mac'i tamamen kapatır; focusOn/focusOff Rahatsız Etme/odak modu")
        var action: Action
        @Guide(description: "Sadece focusOn/focusOff için odağın adı: 'uyku odağını aç' → 'uyku'. Söylenmediyse boş bırak.")
        var focusName: String?
    }

    func refine(_ arguments: Arguments, command: String) -> Arguments {
        let language = AppLanguage.current
        if let focusOn = MacControlRequest.focus(command, language: language) {
            return Arguments(action: focusOn ? .focusOn : .focusOff, focusName: command)
        }
        switch MacControlRequest.power(command, language: language) {
        case .restart: return Arguments(action: .restart, focusName: nil)
        case .shutDown: return Arguments(action: .shutDown, focusName: nil)
        case .logOut: return Arguments(action: .logOut, focusName: nil)
        case nil: return arguments
        }
    }

    /// Power actions close every app, so only an explicit yes runs them; Focus needs a user shortcut.
    func makeCall(_ arguments: Arguments) async -> PreparedToolCall {
        let description = String(describing: arguments)
        switch arguments.action {
        case .restart, .shutDown, .logOut:
            return PreparedToolCall(toolName: name, argumentsDescription: description, risk: .needsConfirmation,
                                    confirmationQuestion: Self.powerQuestion(arguments.action), requiresExplicitYes: true,
                                    execute: { try await Self.power(arguments.action) })
        case .focusOn, .focusOff:
            return await FocusControl.makeCall(toolName: name, turnOn: arguments.action == .focusOn, command: arguments.focusName ?? "")
        default:
            return PreparedToolCall(toolName: name, argumentsDescription: description, risk: risk, confirmationQuestion: nil,
                                    execute: { try await call(arguments: arguments) })
        }
    }

    func call(arguments: Arguments) async throws -> String {
        do {
            switch arguments.action {
            case .focusOn, .focusOff, .restart, .shutDown, .logOut:
                return ToolReply.failure(String(localized: "Bu işlem yalnızca sesli komutla yapılabilir."))
            case .lockScreen:
                try await Self.lockScreen()
                return String(localized: "Ekran kilitlendi.")
            case .screenOff:
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

    private static func powerQuestion(_ action: Action) -> String {
        switch action {
        case .restart: String(localized: "Mac'i yeniden başlatayım mı? Açık uygulamalar kapanacak.")
        case .logOut: String(localized: "Oturumu kapatayım mı? Açık uygulamalar kapanacak.")
        default: String(localized: "Mac'i kapatayım mı? Açık uygulamalar kapanacak.")
        }
    }

    /// System Events asks the apps to quit, so one with unsaved work can still stop it.
    private static func power(_ action: Action) async throws -> String {
        let (command, reply) = switch action {
        case .restart: ("restart", String(localized: "Mac yeniden başlatılıyor."))
        case .logOut: ("log out", String(localized: "Oturum kapatılıyor."))
        default: ("shut down", String(localized: "Mac kapatılıyor."))
        }
        do {
            _ = try await AppleScriptRunner.run("tell application \"System Events\" to \(command)")
            return reply
        } catch {
            return ToolReply.failure(error)
        }
    }

    /// `pmset displaysleepnow` only blanks the screen, which stays unlocked when the password is not
    /// required right away. SACLockScreenImmediate is what the ⌃⌘Q menu item calls; if the private
    /// framework ever goes, System Events presses ⌃⌘Q instead.
    private static func lockScreen() async throws {
        let locked = await MainActor.run { () -> Bool in
            guard let handle = dlopen(loginFramework, RTLD_LAZY), let symbol = dlsym(handle, "SACLockScreenImmediate")
            else { return false }
            _ = unsafeBitCast(symbol, to: (@convention(c) () -> Int32).self)()
            return true
        }
        guard !locked else { return }
        _ = try await AppleScriptRunner.run(#"tell application "System Events" to keystroke "q" using {control down, command down}"#)
    }
}
