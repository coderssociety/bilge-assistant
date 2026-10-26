import AppKit
import FoundationModels

struct OpenAppTool: AssistantTool {
    let name = "openApp"
    let description = "Mac'te bir uygulamayı açar veya öne getirir. Örnek: Safari, Takvim, Hesap Makinesi, Spotify."
    let catalog: AppCatalog

    @Generable
    struct Arguments {
        @Guide(description: "Uygulamanın adı, eksiz yalın hali. Örnek: 'Safari', 'Takvim'")
        var appName: String
    }

    func call(arguments: Arguments) async throws -> String {
        guard let app = await catalog.resolve(arguments.appName) else {
            return ToolReply.failure(String(localized: "'\(arguments.appName)' adında yüklü bir uygulama bulunamadı."))
        }
        do {
            let configuration = NSWorkspace.OpenConfiguration()
            configuration.activates = true
            _ = try await NSWorkspace.shared.openApplication(at: app.url, configuration: configuration)
            return String(localized: "\(app.displayName) açıldı.")
        } catch {
            return ToolReply.failure(error)
        }
    }
}

struct QuitAppTool: AssistantTool {
    let name = "quitApp"
    let description = "Açık bir uygulamayı normal şekilde kapatır. Kaydedilmemiş belge varsa uygulama kendisi sorar."
    let catalog: AppCatalog

    @Generable
    struct Arguments {
        @Guide(description: "Kapatılacak uygulamanın adı. Örnek: 'Spotify'")
        var appName: String
    }

    func call(arguments: Arguments) async throws -> String {
        guard let app = await catalog.resolve(arguments.appName) else {
            return ToolReply.failure(String(localized: "'\(arguments.appName)' adında bir uygulama bulunamadı."))
        }
        return await MainActor.run {
            let running = NSWorkspace.shared.runningApplications.filter {
                $0.bundleURL == app.url || ($0.bundleIdentifier != nil && $0.bundleIdentifier == app.bundleIdentifier)
            }
            guard !running.isEmpty else { return String(localized: "\(app.displayName) zaten kapalı.") }
            let requested = running.map { $0.terminate() }.contains(true)
            return requested
                ? String(localized: "\(app.displayName) kapatılıyor.")
                : ToolReply.failure(String(localized: "\(app.displayName) kapatılamadı."))
        }
    }
}

struct RunningAppsTool: AssistantTool {
    let name = "listRunningApps"
    let description = "Şu anda açık olan uygulamaları ve öndeki uygulamayı listeler."

    @Generable
    struct Arguments {}

    func emptyArguments() -> Arguments? { Arguments() }

    func call(arguments: Arguments) async throws -> String {
        await MainActor.run {
            let apps = NSWorkspace.shared.runningApplications.filter { $0.activationPolicy == .regular }
            let names = apps.compactMap(\.localizedName)
            let front = NSWorkspace.shared.frontmostApplication?.localizedName
            var reply = String(localized: "Açık uygulamalar: \(names.joined(separator: ", ")).")
            if let front { reply += String(localized: " Öndeki: \(front).") }
            return reply
        }
    }
}
