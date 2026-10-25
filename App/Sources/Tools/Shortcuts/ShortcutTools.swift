import AsistanCore
import Foundation
import FoundationModels

/// The user's own Shortcuts are the extension point for anything without a public API
/// (Focus modes, smart home). Running one needs confirmation: a shortcut can do anything.
enum ShortcutsCatalog {
    private static let executable = "/usr/bin/shortcuts"

    static func names() async throws -> [String] {
        let output = try await ProcessRunner.run(executable, ["list"])
        guard output.status == 0 else {
            Log.tools.error("shortcuts list failed (\(output.status)): \(output.standardError)")
            throw ShortcutsError.listFailed
        }
        return output.standardOutput.split(separator: "\n").map(String.init).filter { !$0.isEmpty }
    }

    static func resolve(_ spokenName: String) async throws -> String? {
        let names = try await names()
        let matcher = AppNameMatcher(apps: names.map { .init(id: $0, names: [$0]) })
        return matcher.bestMatch(for: spokenName)?.id
    }

    static func run(_ name: String) async throws -> String {
        let output = try await ProcessRunner.run(executable, ["run", name], timeout: .seconds(60))
        guard output.status == 0 else {
            Log.tools.error("shortcuts run failed (\(output.status)): \(output.standardError)")
            return ToolReply.failure(String(localized: "'\(name)' kestirmesi çalışmadı."))
        }
        return output.standardOutput.isEmpty
            ? String(localized: "'\(name)' kestirmesi çalıştı.")
            : String(localized: "'\(name)' sonucu: \(String(output.standardOutput.prefix(300)))")
    }

    enum ShortcutsError: LocalizedError {
        case listFailed
        var errorDescription: String? {
            String(localized: "Kestirmeler okunamadı.")
        }
    }
}

struct ListShortcutsTool: AssistantTool {
    let name = "listShortcuts"
    let description = "Kestirmeler uygulamasındaki kestirmelerin adlarını listeler."
    let readingLayout: ContinuedReading.Layout? = .list(separator: ", ", perPart: 20)

    @Generable
    struct Arguments {}

    func emptyArguments() -> Arguments? { Arguments() }

    func call(arguments: Arguments) async throws -> String {
        do {
            let names = try await ShortcutsCatalog.names()
            guard !names.isEmpty else { return String(localized: "Hiç kestirmen yok.") }
            return String(localized: "\(names.count) kestirmen var: \(names.joined(separator: ", "))")
        } catch {
            return ToolReply.failure(error)
        }
    }
}

struct RunShortcutTool: AssistantTool {
    let name = "runShortcut"
    let description = "Kestirmeler uygulamasındaki bir kestirmeyi adıyla çalıştırır; başka bir aracın yapmadığı işler için de kullanılır."
    let risk = ToolRisk.needsConfirmation

    @Generable
    struct Arguments {
        @Guide(description: "Kestirmenin adı, örn. 'Sabah rutini'")
        var shortcutName: String
    }

    func makeCall(_ arguments: Arguments) async -> PreparedToolCall {
        let resolved: String?
        do {
            resolved = try await ShortcutsCatalog.resolve(arguments.shortcutName)
        } catch {
            return .unavailable(name, message: error.localizedDescription)
        }
        guard let shortcut = resolved else {
            return .unavailable(name, message: String(localized: "'\(arguments.shortcutName)' adında bir kestirme bulamadım."))
        }
        return PreparedToolCall(
            toolName: name,
            argumentsDescription: shortcut,
            risk: risk,
            confirmationQuestion: String(localized: "'\(shortcut)' kestirmesini çalıştırayım mı?"),
            execute: { try await ShortcutsCatalog.run(shortcut) })
    }

    /// Only the confirmed path from `makeCall` runs shortcuts.
    func call(arguments: Arguments) async throws -> String {
        ToolReply.failure(String(localized: "Kestirmeler yalnızca sesli onayla çalıştırılabilir."))
    }
}
