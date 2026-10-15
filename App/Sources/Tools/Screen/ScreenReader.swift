import AppKit
import CoreGraphics
import ScreenCaptureKit
import Vision

enum ScreenReaderError: LocalizedError {
    case permissionMissing
    case nothingToCapture

    var errorDescription: String? {
        switch self {
        case .permissionMissing:
            String(localized: "Ekranı okumak için Ekran Kaydı izni gerekiyor. Sistem Ayarları > Gizlilik ve Güvenlik > Ekran ve Sistem Sesi Kaydı'ndan Bilge'ye izin ver.")
        case .nothingToCapture:
            String(localized: "Okunacak bir pencere bulamadım.")
        }
    }
}

/// Captures the front window (or the main display) in memory and reads its text with Vision.
/// Nothing is written to disk.
enum ScreenReader {
    enum Scope: Sendable { case frontWindow, wholeScreen }

    private static let maxCharacters = 2500

    static func readText(scope: Scope) async throws -> String {
        guard CGPreflightScreenCaptureAccess() else {
            CGRequestScreenCaptureAccess()
            throw ScreenReaderError.permissionMissing
        }
        let image = try await capture(scope)
        let text = try await recognizeText(in: image)
        return String(text.prefix(maxCharacters))
    }

    private static func capture(_ scope: Scope) async throws -> CGImage {
        let content = try await SCShareableContent.excludingDesktopWindows(true, onScreenWindowsOnly: true)
        let ownPID = ProcessInfo.processInfo.processIdentifier
        let frontPID = await MainActor.run { NSWorkspace.shared.frontmostApplication?.processIdentifier }
        let configuration = SCStreamConfiguration()
        configuration.showsCursor = false
        let scale = await MainActor.run { NSScreen.main?.backingScaleFactor ?? 2 }

        if scope == .frontWindow, let frontPID, frontPID != ownPID,
           let window = content.windows
               .filter({ $0.owningApplication?.processID == frontPID && $0.isOnScreen && $0.windowLayer == 0 })
               .max(by: { $0.frame.width * $0.frame.height < $1.frame.width * $1.frame.height }) {
            configuration.width = Int(window.frame.width * scale)
            configuration.height = Int(window.frame.height * scale)
            return try await SCScreenshotManager.captureImage(
                contentFilter: SCContentFilter(desktopIndependentWindow: window), configuration: configuration)
        }
        guard let display = content.displays.first else { throw ScreenReaderError.nothingToCapture }
        let ownApps = content.applications.filter { $0.processID == ownPID }
        configuration.width = Int(CGFloat(display.width) * scale)
        configuration.height = Int(CGFloat(display.height) * scale)
        return try await SCScreenshotManager.captureImage(
            contentFilter: SCContentFilter(display: display, excludingApplications: ownApps, exceptingWindows: []),
            configuration: configuration)
    }

    private static func recognizeText(in image: CGImage) async throws -> String {
        var request = RecognizeTextRequest()
        request.recognitionLevel = .accurate
        request.usesLanguageCorrection = true
        let wanted = [Locale.Language(identifier: "tr-TR"), Locale.Language(identifier: "en-US")]
        request.recognitionLanguages = wanted.filter { request.supportedRecognitionLanguages.contains($0) }
        let observations = try await request.perform(on: image)
        return observations.compactMap { $0.topCandidates(1).first?.string }.joined(separator: "\n")
    }
}
