import AsistanCore
import CryptoKit
import Foundation
import Observation

enum UpdateInstallError: LocalizedError {
    case noPackage
    case notReplaceable
    case download(Int)
    case noChecksum
    case checksumMismatch
    case unexpectedApp
    case toolFailed(String)

    var errorDescription: String? {
        switch self {
        case .noPackage: String(localized: "Bu sürümde Mac paketi ya da sağlama listesi yok.")
        case .notReplaceable:
            String(localized: "\(AppIdentity.name) bulunduğu klasörde güncellenemiyor; Uygulamalar klasörüne taşıyıp yeniden dene.")
        case let .download(status): String(localized: "İndirilemedi (\(status)).")
        case .noChecksum: String(localized: "Sağlama listesinde Mac paketi yok.")
        case .checksumMismatch: String(localized: "İndirilen paket sağlama toplamıyla uyuşmuyor; kurulmadı.")
        case .unexpectedApp: String(localized: "Paketin içinden beklenen uygulama çıkmadı; kurulmadı.")
        case let .toolFailed(tool): String(localized: "\(tool) çalışmadı.")
        }
    }
}

/// Puts a newer release in place of this app and starts it again: the DMG is fetched from the project's release, must
/// match the release's SHA256SUMS, and must hold this same app (bundle id, the release's version, a valid signature)
/// before anything is replaced. The swap itself happens after Bilge quits (`AppRelauncher.replace`).
@MainActor
@Observable
final class UpdateInstaller {
    enum State: Equatable {
        case idle
        case working(String)
        case failed(String)
    }

    private(set) var state: State = .idle

    private static let toolTimeout: Duration = .seconds(120)

    /// A copy run from the DMG or from a folder it cannot write to (macOS runs a downloaded app from a read-only
    /// "translocated" copy until it is moved) cannot put a new version in its own place.
    static var canReplaceItself: Bool {
        let app = Bundle.main.bundleURL
        return !app.path.contains("/AppTranslocation/")
            && FileManager.default.isWritableFile(atPath: app.deletingLastPathComponent().path)
    }

    var isWorking: Bool {
        if case .working = state { true } else { false }
    }

    func install(_ release: ReleaseCheck.Release) async {
        guard !isWorking else { return }
        state = .working(String(localized: "İndiriliyor…"))
        do {
            let staged = try await stage(release)
            Log.app.info("Installing Bilge \(release.version, privacy: .public) and relaunching")
            AppRelauncher.replace(with: staged)
        } catch {
            Log.app.error("Update failed: \(error.localizedDescription, privacy: .public)")
            state = .failed(error.localizedDescription)
        }
    }

    /// The verified new app, copied next to this one; the caller swaps them.
    private func stage(_ release: ReleaseCheck.Release) async throws -> URL {
        guard let package = release.macPackage, let sums = release.checksums else { throw UpdateInstallError.noPackage }
        guard Self.canReplaceItself else { throw UpdateInstallError.notReplaceable }
        let work = FileManager.default.temporaryDirectory.appending(path: "bilge-update-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: work, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: work) }

        let (sumsFile, _) = try await Self.download(sums.url, to: work.appending(path: sums.name))
        let sumsText = try String(contentsOf: sumsFile, encoding: .utf8)
        guard let expected = ReleaseCheck.checksums(in: sumsText)[package.name] else { throw UpdateInstallError.noChecksum }
        let (dmg, _) = try await Self.download(package.url, to: work.appending(path: package.name))
        guard try Self.sha256(of: dmg) == expected else { throw UpdateInstallError.checksumMismatch }

        state = .working(String(localized: "Kuruluyor…"))
        let mount = work.appending(path: "mount", directoryHint: .isDirectory)
        try await Self.run("/usr/bin/hdiutil", ["attach", "-nobrowse", "-readonly", "-noautoopen", "-mountpoint", mount.path, dmg.path])
        do {
            let newApp = mount.appending(path: "Bilge.app", directoryHint: .isDirectory)
            try await Self.verify(newApp, version: release.version)
            let staged = Bundle.main.bundleURL.deletingLastPathComponent()
                .appending(path: ".Bilge-update-\(UUID().uuidString).app", directoryHint: .isDirectory)
            try await Self.run("/usr/bin/ditto", [newApp.path, staged.path])
            try? await Self.run("/usr/bin/hdiutil", ["detach", mount.path, "-force"])
            return staged
        } catch {
            try? await Self.run("/usr/bin/hdiutil", ["detach", mount.path, "-force"])
            throw error
        }
    }

    private static func download(_ url: URL, to destination: URL) async throws -> (URL, URLResponse) {
        let (temporary, response) = try await URLSession.shared.download(from: url)
        let status = (response as? HTTPURLResponse)?.statusCode ?? 0
        guard status == 200 else { throw UpdateInstallError.download(status) }
        try FileManager.default.moveItem(at: temporary, to: destination)
        return (destination, response)
    }

    private static func sha256(of file: URL) throws -> String {
        let handle = try FileHandle(forReadingFrom: file)
        defer { try? handle.close() }
        var hasher = SHA256()
        while let chunk = try handle.read(upToCount: 1 << 20), !chunk.isEmpty {
            hasher.update(data: chunk)
        }
        return hasher.finalize().map { String(format: "%02x", $0) }.joined()
    }

    /// The same app as this one, at the release's version, with an intact signature.
    private static func verify(_ app: URL, version: String) async throws {
        guard let info = NSDictionary(contentsOf: app.appending(path: "Contents/Info.plist")),
              info["CFBundleIdentifier"] as? String == Bundle.main.bundleIdentifier,
              info["CFBundleShortVersionString"] as? String == version
        else { throw UpdateInstallError.unexpectedApp }
        try await run("/usr/bin/codesign", ["--verify", "--deep", "--strict", app.path])
    }

    private static func run(_ tool: String, _ arguments: [String]) async throws {
        let output = try await ProcessRunner.run(tool, arguments, timeout: toolTimeout)
        guard output.status == 0 else {
            Log.app.error("\(tool, privacy: .public) failed (\(output.status)): \(output.standardError, privacy: .public)")
            throw UpdateInstallError.toolFailed(URL(filePath: tool).lastPathComponent)
        }
    }
}
