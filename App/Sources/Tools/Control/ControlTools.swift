import AppKit
import AsistanCore
import FoundationModels

struct WindowTool: AssistantTool {
    let name = "windowControl"
    let description = "Öndeki pencereyi küçültür, tam ekran yapar, ekranın soluna/sağına yerleştirir ya da büyütür; bir uygulamayı ya da diğer uygulamaları gizler."

    @Generable
    enum Action {
        case minimize, fullScreen, leftHalf, rightHalf, maximize, hideApp, hideOthers, showAll
    }

    @Generable
    struct Arguments {
        var action: Action
        @Guide(description: "hideApp için gizlenecek uygulamanın eksiz adı; öndeki uygulama için boş bırak")
        var appName: String?
    }

    func call(arguments: Arguments) async throws -> String {
        do {
            return try await MainActor.run { try Self.perform(arguments) }
        } catch {
            return ToolReply.failure(error)
        }
    }

    @MainActor
    private static func perform(_ arguments: Arguments) throws -> String {
        switch arguments.action {
        case .hideApp:
            guard let app = runningApp(named: arguments.appName) else { return ToolReply.failure("Gizlenecek uygulamayı bulamadım.") }
            app.hide()
            return "\(app.localizedName ?? "Uygulama") gizlendi."
        case .hideOthers:
            let front = AccessibilityControl.frontApplication()
            for app in regularApps() where app != front { app.hide() }
            return "Diğer uygulamalar gizlendi."
        case .showAll:
            regularApps().forEach { $0.unhide() }
            return "Tüm uygulamalar gösteriliyor."
        case .minimize:
            AccessibilityControl.set(try AccessibilityControl.focusedWindow(), kAXMinimizedAttribute, kCFBooleanTrue)
            return "Pencere küçültüldü."
        case .fullScreen:
            AccessibilityControl.set(try AccessibilityControl.focusedWindow(), "AXFullScreen", kCFBooleanTrue)
            return "Pencere tam ekran yapıldı."
        case .leftHalf, .rightHalf, .maximize:
            let window = try AccessibilityControl.focusedWindow()
            guard let screen = NSScreen.main, let primary = NSScreen.screens.first else { throw AccessibilityError.noWindow }
            var frame = screen.visibleFrame
            if arguments.action != .maximize {
                frame.size.width /= 2
                if arguments.action == .rightHalf { frame.origin.x += frame.width }
            }
            // AX positions are measured from the top-left of the primary screen.
            var origin = CGPoint(x: frame.minX, y: primary.frame.maxY - frame.maxY)
            var size = frame.size
            if let position = AXValueCreate(.cgPoint, &origin) { AccessibilityControl.set(window, kAXPositionAttribute, position) }
            if let dimensions = AXValueCreate(.cgSize, &size) { AccessibilityControl.set(window, kAXSizeAttribute, dimensions) }
            return switch arguments.action {
            case .leftHalf: "Pencere ekranın soluna yerleşti."
            case .rightHalf: "Pencere ekranın sağına yerleşti."
            default: "Pencere büyütüldü."
            }
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

/// "Şunu yaz: ..." types dictated text into the focused field. It never presses Return, and refuses
/// terminals, where typed text could become a command.
struct TypeTextTool: AssistantTool {
    let name = "typeText"
    let description = "Söylenen metni öndeki uygulamada imlecin olduğu yere yazar (dikte). Enter'a basmaz."
    private static let terminalBundleIDs: Set<String> = [
        "com.apple.Terminal", "com.googlecode.iterm2", "dev.warp.Warp-Stable", "com.mitchellh.ghostty",
        "net.kovidgoyal.kitty", "io.alacritty", "com.github.wez.wezterm",
    ]

    @Generable
    struct Arguments {
        @Guide(description: "Yazılacak metin, kullanıcının söylediği gibi")
        var text: String
    }

    func call(arguments: Arguments) async throws -> String {
        let text = arguments.text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty else { return ToolReply.failure("Ne yazacağımı anlayamadım.") }
        let front = await MainActor.run { AccessibilityControl.frontApplication() }
        guard let front else { return ToolReply.failure("Yazı yazılacak bir uygulama önde değil.") }
        if let bundleID = front.bundleIdentifier, Self.terminalBundleIDs.contains(bundleID) {
            return ToolReply.failure("Güvenlik için terminale yazı yazmıyorum.")
        }
        do {
            try await AccessibilityControl.type(text)
            return "Yazdım."
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
            guard let text, !text.isEmpty else { return ToolReply.failure("Seçili bir metin bulamadım.") }
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
