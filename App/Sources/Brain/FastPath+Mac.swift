import AsistanCore

extension FastPath {
    static func action(for window: QuickIntent.Window) -> WindowTool.Action {
        switch window {
        case .minimize: .minimize
        case .fullScreen: .fullScreen
        case .leftHalf: .leftHalf
        case .rightHalf: .rightHalf
        case .maximize: .maximize
        case .hideOthers: .hideOthers
        }
    }

    static func topic(for topic: QuickIntent.SystemInfoTopic) -> SystemInfoTool.Topic {
        switch topic {
        case .disk: .disk
        case .uptime: .uptime
        case .osVersion: .osVersion
        case .network: .network
        }
    }

    static func pane(for pane: QuickIntent.SettingsPane) -> SettingsPaneTool.Pane {
        switch pane {
        case .wifi: .wifi
        case .bluetooth: .bluetooth
        case .network: .network
        case .sound: .sound
        case .displays: .displays
        case .battery: .battery
        case .notifications: .notifications
        case .focus: .focus
        case .privacy: .privacy
        case .keyboard: .keyboard
        case .general: .general
        case .wallpaper: .wallpaper
        case .softwareUpdate: .softwareUpdate
        case .storage: .storage
        case .accessibility: .accessibility
        case .trackpad: .trackpad
        case .mouse: .mouse
        }
    }
}
