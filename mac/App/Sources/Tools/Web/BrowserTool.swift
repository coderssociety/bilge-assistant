import AppKit
import AsistanCore
import FoundationModels

/// "Sonraki sekmeye geç", "geri git", "aşağı kaydır", "bu sayfada fiyatı ara". Keys go only to a
/// browser that is in front (one is brought forward first), so "sekmeyi kapat" can never close another
/// app's window. Scrolling works in whatever app is in front.
struct BrowserTool: RuleRoutedTool {
    let name = "browserControl"
    let description = "Tarayıcıda sekmeler arasında geçer, sekme açar ve kapatır, geri ve ileri gider, sayfayı yeniler, kaydırır ve sayfada arama yapar."

    @Generable
    struct Arguments {
        @Guide(description: "Kullanıcının isteği, olduğu gibi")
        var command: String
    }

    private enum Key {
        static let tab: CGKeyCode = 48
        static let returnKey: CGKeyCode = 36
        static let left: CGKeyCode = 123
        static let right: CGKeyCode = 124
        static let down: CGKeyCode = 125
        static let up: CGKeyCode = 126
        static let pageDown: CGKeyCode = 121
        static let pageUp: CGKeyCode = 116
        static let r: CGKeyCode = 15
        static let t: CGKeyCode = 17
        static let w: CGKeyCode = 13
        static let f: CGKeyCode = 3
    }

    private static let activationTimeout: Duration = .seconds(1)
    private static let findFieldDelay: Duration = .milliseconds(250)

    @MainActor
    func claims(_ command: String) -> Bool {
        BrowserCommand.parse(command, language: AppLanguage.current) != nil
    }

    func arguments(fromCommand command: String) -> Arguments? {
        Arguments(command: command)
    }

    func call(arguments: Arguments) async throws -> String {
        guard let command = BrowserCommand.parse(arguments.command, language: AppLanguage.current) else {
            return ToolReply.failure(String(localized: "Tarayıcıda ne yapmamı istediğini anlayamadım."))
        }
        do {
            return try await Self.perform(command)
        } catch {
            return ToolReply.failure(error)
        }
    }

    @MainActor
    private static func perform(_ command: BrowserCommand) async throws -> String {
        switch command {
        case .scrollDown: try AccessibilityControl.press(Key.pageDown); return String(localized: "Aşağı kaydırdım.")
        case .scrollUp: try AccessibilityControl.press(Key.pageUp); return String(localized: "Yukarı kaydırdım.")
        case .bottom:
            try AccessibilityControl.press(Key.down, flags: .maskCommand)
            return String(localized: "Sonuna indim.")
        case .top:
            try AccessibilityControl.press(Key.up, flags: .maskCommand)
            return String(localized: "Başına çıktım.")
        default: break
        }
        guard let browser = await frontBrowser() else {
            return ToolReply.failure(String(localized: "Açık bir tarayıcı yok."))
        }
        switch command {
        case .nextTab: try AccessibilityControl.press(Key.tab, flags: .maskControl)
        case .previousTab: try AccessibilityControl.press(Key.tab, flags: [.maskControl, .maskShift])
        case .newTab: try AccessibilityControl.press(Key.t, flags: .maskCommand)
        case .closeTab: try AccessibilityControl.press(Key.w, flags: .maskCommand)
        case .reopenTab: try AccessibilityControl.press(Key.t, flags: [.maskCommand, .maskShift])
        case .back: try AccessibilityControl.press(Key.left, flags: .maskCommand)
        case .forward: try AccessibilityControl.press(Key.right, flags: .maskCommand)
        case .reload: try AccessibilityControl.press(Key.r, flags: .maskCommand)
        case let .find(text):
            try AccessibilityControl.press(Key.f, flags: .maskCommand)
            try await Task.sleep(for: findFieldDelay)
            try await AccessibilityControl.type(TypedText.sanitized(text), into: browser.processIdentifier)
            try AccessibilityControl.press(Key.returnKey)
            return String(localized: "Sayfada '\(text)' arıyorum.")
        case let .tab(index):
            return try await selectTab(index, in: browser)
        case .lastTab:
            return try await selectTab(nil, in: browser)
        case let .tabNamed(title):
            return try await selectTab(named: title, in: browser)
        case .scrollDown, .scrollUp, .top, .bottom:
            break
        }
        return reply(for: command)
    }

    private static func reply(for command: BrowserCommand) -> String {
        switch command {
        case .nextTab: String(localized: "Sonraki sekme.")
        case .previousTab: String(localized: "Önceki sekme.")
        case .newTab: String(localized: "Yeni sekme açtım.")
        case .closeTab: String(localized: "Sekmeyi kapattım.")
        case .reopenTab: String(localized: "Kapattığın sekmeyi geri açtım.")
        case .back: String(localized: "Geri gittim.")
        case .forward: String(localized: "İleri gittim.")
        case .reload: String(localized: "Sayfayı yeniledim.")
        default: String(localized: "Tamam.")
        }
    }

    /// The browser in front, or the first running one brought forward; nil if none is running or it
    /// did not come forward (keys must not reach another app).
    @MainActor
    private static func frontBrowser() async -> NSRunningApplication? {
        if let front = AccessibilityControl.frontApplication(), BrowserPage.isBrowser(front.bundleIdentifier) { return front }
        guard let browser = NSWorkspace.shared.runningApplications.first(where: { BrowserPage.isBrowser($0.bundleIdentifier) }) else {
            return nil
        }
        browser.activate()
        let deadline = ContinuousClock.now + activationTimeout
        while ContinuousClock.now < deadline {
            if NSWorkspace.shared.frontmostApplication?.processIdentifier == browser.processIdentifier { return browser }
            try? await Task.sleep(for: .milliseconds(50))
        }
        return nil
    }

    /// Tab `index` from 1, or the last one for nil.
    @MainActor
    private static func selectTab(_ index: Int?, in browser: NSRunningApplication) async throws -> String {
        guard let identifier = browser.bundleIdentifier, BrowserPage.isScriptable(identifier) else {
            return ToolReply.failure(String(localized: "Bu tarayıcıda sekmelere numarayla geçemiyorum."))
        }
        let count = try await BrowserPage.tabTitles(in: identifier).count
        let target = index ?? count
        guard (1...max(count, 1)).contains(target), count > 0 else {
            return ToolReply.failure(String(localized: "Bu pencerede \(count) sekme var."))
        }
        try await BrowserPage.selectTab(target, in: identifier)
        return String(localized: "\(target). sekme.")
    }

    @MainActor
    private static func selectTab(named title: String, in browser: NSRunningApplication) async throws -> String {
        guard let identifier = browser.bundleIdentifier, BrowserPage.isScriptable(identifier) else {
            return ToolReply.failure(String(localized: "Bu tarayıcıda sekmelere adıyla geçemiyorum."))
        }
        let titles = try await BrowserPage.tabTitles(in: identifier)
        guard let match = PhraseMatcher.bestMatch(for: title, in: titles), let index = titles.firstIndex(of: match) else {
            return ToolReply.failure(String(localized: "'\(title)' adında bir sekme bulamadım."))
        }
        try await BrowserPage.selectTab(index + 1, in: identifier)
        return String(localized: "\(match) sekmesi.")
    }
}
