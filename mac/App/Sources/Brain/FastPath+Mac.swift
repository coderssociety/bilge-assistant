import AsistanCore

extension FastPath {
    static func action(for window: QuickIntent.Window) -> WindowTool.Action {
        switch window {
        case .minimize: .minimize
        case .restore: .restore
        case .close: .close
        case .fullScreen: .fullScreen
        case .exitFullScreen: .exitFullScreen
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

    static func arguments(for brightness: QuickIntent.Brightness) -> BrightnessTool.Arguments {
        switch brightness {
        case .up: .init(action: .increase, level: nil, amount: nil)
        case .down: .init(action: .decrease, level: nil, amount: nil)
        case let .change(amount): .init(action: amount > 0 ? .increase : .decrease, level: nil, amount: abs(amount))
        case let .set(level): .init(action: .set, level: level, amount: nil)
        }
    }

    static func action(for bluetooth: QuickIntent.Bluetooth) -> BluetoothTool.Action {
        switch bluetooth {
        case .on: .on
        case .off: .off
        case .status: .status
        }
    }
}
