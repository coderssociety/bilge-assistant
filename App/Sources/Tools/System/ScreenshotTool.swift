import AppKit
import FoundationModels

struct ScreenshotTool: AssistantTool {
    let name = "takeScreenshot"
    let description = "Ekran görüntüsü alır: tüm ekran, öndeki pencere ya da fareyle seçilen alan; Masaüstü'ne kaydeder ya da panoya kopyalar."
    /// A selection waits for the user to drag a rectangle.
    private static let selectionTimeout: Duration = .seconds(60)

    @Generable
    enum Area {
        case wholeScreen, frontWindow, selection
    }

    @Generable
    struct Arguments {
        @Guide(description: "Belirtilmediyse wholeScreen")
        var area: Area
        @Guide(description: "Panoya kopyalanması istendiyse true, yoksa false")
        var toClipboard: Bool
    }

    func call(arguments: Arguments) async throws -> String {
        guard ScreenReader.hasCaptureAccess() else {
            return ToolReply.failure(String(localized: "Ekran görüntüsü almak için Ekran Kaydı izni gerekiyor. Sistem Ayarları > Gizlilik ve Güvenlik > Ekran ve Sistem Sesi Kaydı'ndan Bilge'ye izin ver."))
        }
        var options = ["-x"]
        switch arguments.area {
        case .wholeScreen: break
        case .selection: options.append("-i")
        case .frontWindow:
            guard let windowID = await Self.frontWindowID() else {
                return ToolReply.failure(String(localized: "Öndeki pencereyi bulamadım."))
            }
            options.append("-l\(windowID)")
        }
        let file = Self.destination()
        options.append(contentsOf: arguments.toClipboard ? ["-c"] : [file.path(percentEncoded: false)])
        do {
            let timeout = arguments.area == .selection ? Self.selectionTimeout : ProcessRunner.defaultTimeout
            let output = try await ProcessRunner.run("/usr/sbin/screencapture", options, timeout: timeout)
            guard output.status == 0 else {
                return ToolReply.failure(String(localized: "Ekran görüntüsü alınamadı."))
            }
            if arguments.toClipboard { return String(localized: "Ekran görüntüsü panoya kopyalandı.") }
            guard FileManager.default.fileExists(atPath: file.path(percentEncoded: false)) else {
                return String(localized: "Ekran görüntüsü alınmadı.")
            }
            return String(localized: "Ekran görüntüsü Masaüstü'ne kaydedildi.")
        } catch {
            return ToolReply.failure(error)
        }
    }

    private static func destination() -> URL {
        let stamp = Date.now.formatted(.verbatim(
            "\(year: .defaultDigits)-\(month: .twoDigits)-\(day: .twoDigits) \(hour: .twoDigits(clock: .twentyFourHour, hourCycle: .zeroBased)).\(minute: .twoDigits).\(second: .twoDigits)",
            timeZone: .current, calendar: .current))
        return URL.desktopDirectory.appending(path: "Ekran Resmi \(stamp).png")
    }

    @MainActor
    private static func frontWindowID() -> Int? {
        guard let pid = NSWorkspace.shared.frontmostApplication?.processIdentifier,
              let windows = CGWindowListCopyWindowInfo([.optionOnScreenOnly, .excludeDesktopElements], kCGNullWindowID) as? [[String: Any]]
        else { return nil }
        return windows.first { ($0[kCGWindowOwnerPID as String] as? pid_t) == pid && ($0[kCGWindowLayer as String] as? Int) == 0 }?[kCGWindowNumber as String] as? Int
    }
}
