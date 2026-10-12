import AppKit
import AsistanCore

/// Installed applications with their localized ("Takvim") and bundle ("Calendar") names.
actor AppCatalog {
    struct Entry: Sendable {
        let url: URL
        let bundleIdentifier: String?
        let displayName: String
    }

    private static let searchRoots = [
        "/Applications", "/Applications/Utilities", "/System/Applications", "/System/Applications/Utilities",
        NSHomeDirectory() + "/Applications",
    ]
    private static let refreshInterval: TimeInterval = 300

    private var entries: [String: Entry] = [:]
    private var matcher = AppNameMatcher(apps: [])
    private var lastRefresh: Date?

    func resolve(_ spokenName: String) -> Entry? {
        refreshIfNeeded()
        return matcher.bestMatch(for: spokenName).flatMap { entries[$0.id] }
    }

    private func refreshIfNeeded() {
        if let lastRefresh, Date.now.timeIntervalSince(lastRefresh) < Self.refreshInterval { return }
        var found: [String: Entry] = [:]
        var apps: [AppNameMatcher.App] = []
        let fileManager = FileManager.default
        for root in Self.searchRoots {
            guard let items = try? fileManager.contentsOfDirectory(atPath: root) else { continue }
            for item in items where item.hasSuffix(".app") {
                let url = URL(filePath: root).appending(path: item)
                let bundle = Bundle(url: url)
                let fileName = String(item.dropLast(4))
                let localized = fileManager.displayName(atPath: url.path).replacingOccurrences(of: ".app", with: "")
                let bundleName = bundle?.object(forInfoDictionaryKey: "CFBundleName") as? String
                let id = url.path
                found[id] = Entry(url: url, bundleIdentifier: bundle?.bundleIdentifier, displayName: localized)
                apps.append(.init(id: id, names: Array(Set([localized, fileName, bundleName].compactMap { $0 }))))
            }
        }
        entries = found
        matcher = AppNameMatcher(apps: apps)
        lastRefresh = .now
    }
}
