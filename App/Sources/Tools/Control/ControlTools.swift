import AppKit
import AsistanCore
import FoundationModels

struct WindowTool: AssistantTool {
    let name = "windowControl"
    let description = "Öndeki pencereyi küçültür, geri getirir, kapatır, tam ekran yapar ya da tam ekrandan çıkarır, ekranın soluna/sağına yerleştirir ya da büyütür; bir uygulamayı ya da diğer uygulamaları gizler."
    /// How far a window may be from the screen's visible frame and still count as zoomed to fill it.
    private static let zoomTolerance: CGFloat = 8
    /// Time for a closed or resized window to settle before it is checked.
    private static let settleDelay: Duration = .milliseconds(300)

    @Generable
    enum Action {
        case minimize, restore, close, fullScreen, exitFullScreen, leftHalf, rightHalf, maximize, hideApp, hideOthers, showAll
    }

    @Generable
    struct Arguments {
        @Guide(description: "restore küçültülmüş pencereyi geri getirir ya da büyütülmüş pencereyi eski boyutuna döndürür")
        var action: Action
        @Guide(description: "hideApp için gizlenecek uygulamanın eksiz adı; öndeki uygulama için boş bırak")
        var appName: String?
    }

    func call(arguments: Arguments) async throws -> String {
        do {
            return try await Self.perform(arguments)
        } catch {
            return ToolReply.failure(error)
        }
    }

    @MainActor
    private static func perform(_ arguments: Arguments) async throws -> String {
        switch arguments.action {
        case .hideApp:
            guard let app = runningApp(named: arguments.appName) else {
                return ToolReply.failure(String(localized: "Gizlenecek uygulamayı bulamadım."))
            }
            app.hide()
            return String(localized: "\(app.localizedName ?? String(localized: "Uygulama")) gizlendi.")
        case .hideOthers:
            let front = AccessibilityControl.frontApplication()
            for app in regularApps() where app != front { app.hide() }
            return String(localized: "Diğer uygulamalar gizlendi.")
        case .showAll:
            regularApps().forEach { $0.unhide() }
            return String(localized: "Tüm uygulamalar gösteriliyor.")
        case .minimize:
            return AccessibilityControl.set(try AccessibilityControl.focusedWindow(), kAXMinimizedAttribute, kCFBooleanTrue)
                ? String(localized: "Pencere küçültüldü.")
                : ToolReply.failure(String(localized: "Pencere küçültülemedi."))
        case .fullScreen:
            return AccessibilityControl.set(try AccessibilityControl.focusedWindow(), "AXFullScreen", kCFBooleanTrue)
                ? String(localized: "Pencere tam ekran yapıldı.")
                : ToolReply.failure(String(localized: "Bu pencere tam ekran yapılamadı."))
        case .exitFullScreen:
            return try exitFullScreen(AccessibilityControl.focusedWindow())
        case .restore:
            return try await restore()
        case .close:
            return try await close()
        case .leftHalf, .rightHalf, .maximize:
            return try place(arguments.action)
        }
    }

    @MainActor
    private static func exitFullScreen(_ window: AXUIElement) -> String {
        guard AccessibilityControl.attribute(window, "AXFullScreen") as? Bool == true else {
            return ToolReply.failure(String(localized: "Pencere tam ekranda değil."))
        }
        return AccessibilityControl.set(window, "AXFullScreen", kCFBooleanFalse)
            ? String(localized: "Pencere tam ekrandan çıktı.")
            : ToolReply.failure(String(localized: "Pencere tam ekrandan çıkarılamadı."))
    }

    /// Brings back a minimized window, else leaves full screen, else un-zooms a window that fills the
    /// screen. The zoom button toggles, so it is only pressed on a filling window, and the size is
    /// checked afterwards: a window resized by hand has no smaller size to return to.
    @MainActor
    private static func restore() async throws -> String {
        let windows = try AccessibilityControl.frontWindows()
        if let minimized = windows.first(where: { AccessibilityControl.attribute($0, kAXMinimizedAttribute) as? Bool == true }) {
            return AccessibilityControl.set(minimized, kAXMinimizedAttribute, kCFBooleanFalse)
                ? String(localized: "Pencere geri getirildi.")
                : ToolReply.failure(String(localized: "Pencere geri getirilemedi."))
        }
        let window = try AccessibilityControl.focusedWindow()
        if AccessibilityControl.attribute(window, "AXFullScreen") as? Bool == true { return exitFullScreen(window) }
        guard let before = AccessibilityControl.size(of: window), let screen = NSScreen.main?.visibleFrame.size,
              abs(before.width - screen.width) <= zoomTolerance, abs(before.height - screen.height) <= zoomTolerance
        else { return ToolReply.failure(String(localized: "Geri alınacak küçültülmüş, tam ekran ya da büyütülmüş bir pencere yok.")) }
        guard AccessibilityControl.pressButton(kAXZoomButtonAttribute, of: window) else {
            return ToolReply.failure(String(localized: "Pencere eski boyutuna döndürülemedi."))
        }
        try await Task.sleep(for: settleDelay)
        return AccessibilityControl.size(of: window) != before
            ? String(localized: "Pencere eski boyutuna döndü.")
            : ToolReply.failure(String(localized: "Pencerenin daha küçük bir önceki boyutu yok."))
    }

    /// An app may ask to save first, so the window is checked after the press.
    @MainActor
    private static func close() async throws -> String {
        let window = try AccessibilityControl.focusedWindow()
        guard AccessibilityControl.pressButton(kAXCloseButtonAttribute, of: window) else {
            return ToolReply.failure(String(localized: "Pencere kapatılamadı."))
        }
        try await Task.sleep(for: settleDelay)
        let stillOpen = try AccessibilityControl.frontWindows().contains { CFEqual($0, window) }
        return stillOpen
            ? String(localized: "Pencere hâlâ açık; uygulama kapatmadan önce bir şey soruyor olabilir.")
            : String(localized: "Pencere kapatıldı.")
    }

    @MainActor
    private static func place(_ action: Action) throws -> String {
        let window = try AccessibilityControl.focusedWindow()
        guard let screen = NSScreen.main, let primary = NSScreen.screens.first else { throw AccessibilityError.noWindow }
        var frame = screen.visibleFrame
        if action != .maximize {
            frame.size.width /= 2
            if action == .rightHalf { frame.origin.x += frame.width }
        }
        // AX positions are measured from the top-left of the primary screen.
        var origin = CGPoint(x: frame.minX, y: primary.frame.maxY - frame.maxY)
        var size = frame.size
        guard let position = AXValueCreate(.cgPoint, &origin), let dimensions = AXValueCreate(.cgSize, &size),
              AccessibilityControl.set(window, kAXPositionAttribute, position),
              AccessibilityControl.set(window, kAXSizeAttribute, dimensions)
        else { return ToolReply.failure(String(localized: "Bu pencere taşınamadı ya da boyutlandırılamadı.")) }
        return switch action {
        case .leftHalf: String(localized: "Pencere ekranın soluna yerleşti.")
        case .rightHalf: String(localized: "Pencere ekranın sağına yerleşti.")
        default: String(localized: "Pencere büyütüldü.")
        }
    }

    @MainActor
    private static func regularApps() -> [NSRunningApplication] {
        let own = ProcessInfo.processInfo.processIdentifier
        return NSWorkspace.shared.runningApplications.filter { $0.activationPolicy == .regular && $0.processIdentifier != own }
    }

    @MainActor
    private static func runningApp(named name: String?) -> NSRunningApplication? {
        guard let name, !name.trimmingCharacters(in: .whitespaces).isEmpty else { return AccessibilityControl.frontApplication() }
        let apps = regularApps()
        let matcher = AppNameMatcher(apps: apps.map { .init(id: String($0.processIdentifier), names: [$0.localizedName ?? ""]) })
        guard let match = matcher.bestMatch(for: name) else { return nil }
        return apps.first { String($0.processIdentifier) == match.id }
    }
}

/// "Şunu yaz: ..." types dictated text into the focused field. Control characters are removed, so it
/// can never press Return or Tab, and it refuses apps where typed text could run as a command or
/// land in a secret store (terminals, code editors, remote desktops, password managers).
struct TypeTextTool: AssistantTool {
    let name = "typeText"
    let description = "Söylenen metni öndeki uygulamada imlecin olduğu yere yazar (dikte). Enter'a basmaz."
    private static let refusedBundleIDs: Set<String> = [
        "com.apple.Terminal", "com.googlecode.iterm2", "dev.warp.Warp-Stable", "dev.warp.Warp", "com.mitchellh.ghostty",
        "net.kovidgoyal.kitty", "io.alacritty", "com.github.wez.wezterm", "co.zeit.hyper", "org.tabby",
        "dev.commandline.waveterm", "com.termius-dmg.mac", "com.microsoft.VSCode", "com.todesktop.230313mzl4w4u92",
        "com.apple.dt.Xcode", "com.microsoft.rdc.macos", "com.apple.ScreenSharing", "com.realvnc.vncviewer",
        "com.1password.1password", "com.bitwarden.desktop", "com.apple.keychainaccess", "com.apple.Passwords",
    ]
    private static let refusedBundlePrefixes = ["com.jetbrains.", "com.sublimetext.", "com.parallels.", "com.vmware."]

    @MainActor
    static func refuses(_ app: NSRunningApplication) -> Bool {
        guard let id = app.bundleIdentifier else { return true }
        return refusedBundleIDs.contains(id) || refusedBundlePrefixes.contains(where: id.hasPrefix)
    }

    @Generable
    struct Arguments {
        @Guide(description: "Yazılacak metin, kullanıcının söylediği gibi")
        var text: String
    }

    func call(arguments: Arguments) async throws -> String {
        let text = TypedText.sanitized(arguments.text)
        guard !text.isEmpty else { return ToolReply.failure(String(localized: "Ne yazacağımı anlayamadım.")) }
        let front = await MainActor.run { AccessibilityControl.frontApplication() }
        guard let front else { return ToolReply.failure(String(localized: "Yazı yazılacak bir uygulama önde değil.")) }
        if await Self.refuses(front) {
            return ToolReply.failure(String(localized: "Güvenlik için terminallere, kod düzenleyicilere, uzak masaüstüne ve parola yöneticilerine yazı yazmıyorum."))
        }
        do {
            try await AccessibilityControl.type(text, into: front.processIdentifier)
            return String(localized: "Yazdım.")
        } catch {
            return ToolReply.failure(error)
        }
    }
}

/// "Seçili metni oku / özetle / çevir". The selection is untrusted text, answered by the tool-less session.
struct ReadSelectionTool: AssistantTool {
    let name = "readSelection"
    let description = "Öndeki uygulamada seçili (işaretlenmiş) metni okur; özetler, çevirir ya da açıklar."
    let answersWithLanguageModel = true
    private static let maxCharacters = 6000

    @Generable
    struct Arguments {
        @Guide(description: "Seçili metinle ne yapılacağı, örn. 'özetle', 'İngilizceye çevir', 'oku'")
        var request: String?
    }

    func call(arguments: Arguments) async throws -> String {
        do {
            let text = try await Self.selection()
            guard let text, !text.isEmpty else { return ToolReply.failure(String(localized: "Seçili bir metin bulamadım.")) }
            return String(text.prefix(Self.maxCharacters))
        } catch {
            return ToolReply.failure(error)
        }
    }

    /// Asks Accessibility first; apps that don't expose the selection get ⌘C, and the clipboard is restored.
    @MainActor
    private static func selection() async throws -> String? {
        if let text = try AccessibilityControl.selectedText(), !text.isEmpty { return text }
        let pasteboard = NSPasteboard.general
        let saved = pasteboard.string(forType: .string)
        let before = pasteboard.changeCount
        AccessibilityControl.copySelection()
        try await Task.sleep(for: .milliseconds(250))
        guard pasteboard.changeCount != before else { return nil }
        let copied = pasteboard.string(forType: .string)
        pasteboard.clearContents()
        if let saved { pasteboard.setString(saved, forType: .string) }
        return copied
    }
}
