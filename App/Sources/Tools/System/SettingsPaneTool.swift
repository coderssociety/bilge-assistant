import AppKit
import FoundationModels

struct SettingsPaneTool: AssistantTool {
    let name = "openSettings"
    let description = "Sistem Ayarları'nın bir bölümünü açar: Wi-Fi, Bluetooth, ses, ekran, pil, bildirimler, gizlilik, klavye, duvar kağıdı, yazılım güncelleme gibi."

    @Generable
    enum Pane {
        case wifi, bluetooth, network, sound, displays, battery, notifications, focus, privacy, keyboard,
             general, appearance, wallpaper, softwareUpdate, users, storage, accessibility, desktopDock,
             lockScreen, printers, trackpad, mouse

        var identifier: String {
            switch self {
            case .wifi: "com.apple.wifi-settings-extension"
            case .bluetooth: "com.apple.BluetoothSettings"
            case .network: "com.apple.Network-Settings.extension"
            case .sound: "com.apple.Sound-Settings.extension"
            case .displays: "com.apple.Displays-Settings.extension"
            case .battery: "com.apple.Battery-Settings.extension"
            case .notifications: "com.apple.Notifications-Settings.extension"
            case .focus: "com.apple.Focus-Settings.extension"
            case .privacy: "com.apple.settings.PrivacySecurity.extension"
            case .keyboard: "com.apple.Keyboard-Settings.extension"
            case .general: "com.apple.systempreferences.GeneralSettings"
            case .appearance: "com.apple.Appearance-Settings.extension"
            case .wallpaper: "com.apple.Wallpaper-Settings.extension"
            case .softwareUpdate: "com.apple.Software-Update-Settings.extension"
            case .users: "com.apple.Users-Groups-Settings.extension"
            case .storage: "com.apple.settings.Storage"
            case .accessibility: "com.apple.Accessibility-Settings.extension"
            case .desktopDock: "com.apple.Desktop-Settings.extension"
            case .lockScreen: "com.apple.Lock-Screen-Settings.extension"
            case .printers: "com.apple.Print-Scan-Settings.extension"
            case .trackpad: "com.apple.Trackpad-Settings.extension"
            case .mouse: "com.apple.Mouse-Settings.extension"
            }
        }

        var turkishName: String {
            switch self {
            case .wifi: "Wi-Fi"
            case .bluetooth: "Bluetooth"
            case .network: "Ağ"
            case .sound: "Ses"
            case .displays: "Ekranlar"
            case .battery: "Pil"
            case .notifications: "Bildirimler"
            case .focus: "Odak"
            case .privacy: "Gizlilik ve Güvenlik"
            case .keyboard: "Klavye"
            case .general: "Genel"
            case .appearance: "Görünüm"
            case .wallpaper: "Duvar Kağıdı"
            case .softwareUpdate: "Yazılım Güncelleme"
            case .users: "Kullanıcılar ve Gruplar"
            case .storage: "Depolama"
            case .accessibility: "Erişilebilirlik"
            case .desktopDock: "Masaüstü ve Dock"
            case .lockScreen: "Kilit Ekranı"
            case .printers: "Yazıcılar ve Tarayıcılar"
            case .trackpad: "İzleme Dörtgeni"
            case .mouse: "Fare"
            }
        }
    }

    @Generable
    struct Arguments {
        @Guide(description: "Açılacak ayar bölümü")
        var pane: Pane
    }

    func call(arguments: Arguments) async throws -> String {
        guard let url = URL(string: "x-apple.systempreferences:\(arguments.pane.identifier)") else {
            return ToolReply.failure("Ayar bölümü açılamadı.")
        }
        let opened = await MainActor.run { NSWorkspace.shared.open(url) }
        return opened ? "\(arguments.pane.turkishName) ayarlarını açtım." : ToolReply.failure("Sistem Ayarları açılamadı.")
    }
}
