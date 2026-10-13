import AsistanCore

/// Turns a rule-recognized QuickIntent into a prepared call on the same tools the model would use.
/// Returns nil whenever the intent cannot be bound with certainty (e.g. no installed app matches),
/// which sends the command to the model instead.
@MainActor
struct FastPath {
    let tools: [String: any AssistantTool]

    func call(for intent: QuickIntent) async -> PreparedToolCall? {
        switch intent {
        case .dateTime:
            return await make("currentDateTime", DateTimeTool.self) { .init() }
        case .battery:
            return await make("batteryStatus", BatteryTool.self) { .init() }
        case .reminders:
            return await make("readReminders", RemindersQueryTool.self) { .init() }
        case let .volume(volume):
            return await make("setVolume", VolumeTool.self) { Self.arguments(for: volume) }
        case let .media(media):
            return await make("controlMusic", MediaTool.self) { .init(action: Self.action(for: media)) }
        case let .system(system):
            return await make("systemAction", SystemActionTool.self) { .init(action: Self.action(for: system)) }
        case let .calendar(range):
            return await make("readCalendar", CalendarQueryTool.self) { .init(range: Self.range(for: range)) }
        case let .calculate(expression):
            return await make("calculate", CalculatorTool.self) { .init(expression: expression) }
        case let .timer(seconds):
            guard let tool = tools["setTimer"] as? SetTimerTool else { return nil }
            return await tool.makeCall(.init(minutes: seconds / 60, seconds: seconds % 60, hour: nil, minute: nil, label: nil))
        case let .alarm(hour, minute):
            guard let tool = tools["setTimer"] as? SetTimerTool else { return nil }
            return await tool.makeCall(.init(minutes: nil, seconds: nil, hour: hour, minute: minute, label: nil))
        case .clipboard:
            return await make("readClipboard", ClipboardReadTool.self) { .init() }
        case let .openFolder(folder):
            return await make("files", FileTool.self) { .init(action: .openFolder, query: nil, folder: Self.folder(for: folder)) }
        case let .timers(action):
            return await make("manageTimers", ManageTimersTool.self) { .init(action: action == .list ? .list : .cancelAll) }
        case let .openApp(name):
            guard let tool = tools["openApp"] as? OpenAppTool, await tool.catalog.resolve(name) != nil else { return nil }
            return await tool.makeCall(.init(appName: name))
        case let .quitApp(name):
            guard let tool = tools["quitApp"] as? QuitAppTool, await tool.catalog.resolve(name) != nil else { return nil }
            return await tool.makeCall(.init(appName: name))
        case .screenshot:
            return await make("takeScreenshot", ScreenshotTool.self) { .init(area: .wholeScreen, toClipboard: false) }
        case let .wifi(on):
            return await make("setWiFi", WiFiTool.self) { .init(power: on ? .on : .off) }
        case let .window(window):
            return await make("windowControl", WindowTool.self) { .init(action: Self.action(for: window), appName: nil) }
        case let .settings(pane):
            return await make("openSettings", SettingsPaneTool.self) { .init(pane: Self.pane(for: pane)) }
        case let .systemInfo(topic):
            return await make("systemInfo", SystemInfoTool.self) { .init(topic: Self.topic(for: topic)) }
        }
    }

    private func make<T: AssistantTool>(_ name: String, _: T.Type, _ arguments: () -> T.Arguments) async -> PreparedToolCall? {
        guard let tool = tools[name] as? T else { return nil }
        return await tool.makeCall(arguments())
    }

    private static func arguments(for volume: QuickIntent.Volume) -> VolumeTool.Arguments {
        switch volume {
        case let .set(level): .init(action: .set, level: level)
        case .up: .init(action: .increase, level: nil)
        case .down: .init(action: .decrease, level: nil)
        case .mute: .init(action: .mute, level: nil)
        case .unmute: .init(action: .unmute, level: nil)
        }
    }

    private static func action(for media: QuickIntent.Media) -> MediaTool.Action {
        switch media {
        case .play: .play
        case .pause: .pause
        case .next: .next
        case .previous: .previous
        case .nowPlaying: .nowPlaying
        }
    }

    private static func action(for system: QuickIntent.System) -> SystemActionTool.Action {
        switch system {
        case .lockScreen: .lockScreen
        case .sleep: .sleep
        case .darkModeOn: .darkModeOn
        case .darkModeOff: .darkModeOff
        }
    }

    private static func folder(for folder: QuickIntent.Folder) -> FileTool.Folder {
        switch folder {
        case .desktop: .desktop
        case .downloads: .downloads
        case .documents: .documents
        }
    }

    private static func range(for range: QuickIntent.CalendarRange) -> CalendarQueryTool.Range {
        switch range {
        case .today: .today
        case .tomorrow: .tomorrow
        case .thisWeek: .thisWeek
        }
    }
}
