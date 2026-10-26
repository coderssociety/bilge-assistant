import AsistanCore
import Foundation
import FoundationModels

/// "Komutlarım neler": the user's own commands from Settings → Commands. Chosen by rule, never by the router model.
struct ListCustomCommandsTool: RuleRoutedTool {
    let name = "listCustomCommands"
    let description = "Kullanıcının Ayarlar'da tanımladığı kendi komutlarının adlarını söyler ('komutlarım neler')."
    let store: CustomCommandStore
    var language = AssistantLanguage.turkish

    @Generable
    struct Arguments {}

    func emptyArguments() -> Arguments? { Arguments() }

    @MainActor
    func claims(_ command: String) -> Bool {
        CustomCommandRequest.asksForList(command, language: language)
    }

    func call(arguments: Arguments) async throws -> String {
        let names = await MainActor.run { store.commands.map(\.name) }
        guard !names.isEmpty else {
            return String(localized: "Henüz bir komutun yok; Bilge Ayarları'ndaki Komutlar sekmesinden ekleyebilirsin.")
        }
        return String(localized: "\(names.count) komutun var: \(names.joined(separator: ", "))")
    }
}

/// "Yedekleme komutunu çalıştır": runs one of the user's commands exactly as written in the settings, without a shell
/// and with nothing spoken added to it. The first run of each command, and of each edited version, reads the command
/// line out and needs a spoken yes; after that, naming the command exactly runs it.
struct RunCustomCommandTool: RuleRoutedTool {
    let name = "runCustomCommand"
    let description = "Kullanıcının Ayarlar'da tanımladığı bir komutu adıyla çalıştırır ('yedekleme komutunu çalıştır')."
    let store: CustomCommandStore
    var language = AssistantLanguage.turkish

    static let timeout: Duration = .seconds(60)
    private static let outputCharacters = 300
    /// The command line is read out in the first question; a very long one is cut there.
    private static let spokenLineCharacters = 200

    @Generable
    struct Arguments {
        @Guide(description: "Kullanıcının isteği, olduğu gibi")
        var request: String
    }

    @MainActor
    func claims(_ command: String) -> Bool {
        guard let spoken = CustomCommandRequest.runName(in: command, language: language) else { return false }
        return store.find(spoken) != nil
    }

    func arguments(fromCommand command: String) -> Arguments? {
        Arguments(request: command)
    }

    func makeCall(_ arguments: Arguments) async -> PreparedToolCall {
        let spoken = CustomCommandRequest.runName(in: arguments.request, language: language) ?? arguments.request
        let (found, approved, names) = await MainActor.run {
            let found = store.find(spoken)
            return (found, found.map(store.isApproved) ?? false, store.commands.map(\.name))
        }
        guard let command = found else {
            return .unavailable(name, message: String(localized: "'\(spoken)' adında bir komutun yok."))
        }
        let store = store
        let execute: @Sendable () async throws -> String = {
            if !approved { try await store.approve(command) }
            return await Self.run(command)
        }
        // Only an approved command named exactly runs without asking: "sunucu" merely resembles "sunucuyu kapat".
        if approved, CustomCommandRequest.namesExactly(spoken, name: command.name, names: names) {
            return PreparedToolCall(toolName: name, argumentsDescription: command.name, risk: .safe,
                                    confirmationQuestion: nil, execute: execute)
        }
        var line = command.line
        if line.count > Self.spokenLineCharacters { line = String(line.prefix(Self.spokenLineCharacters)) + "…" }
        let question = approved
            ? String(localized: "'\(command.name)' komutunu çalıştırayım mı?")
            : String(localized: "'\(command.name)' komutu ilk kez çalışacak: \(line). Çalıştırayım mı?")
        // A command can do anything, so a casual "tamam" from a TV or someone in the room is not enough.
        return PreparedToolCall(toolName: name, argumentsDescription: command.name, risk: .needsConfirmation,
                                confirmationQuestion: question, requiresExplicitYes: true, execute: execute)
    }

    /// Only the path from `makeCall` runs commands.
    func call(arguments: Arguments) async throws -> String {
        ToolReply.failure(String(localized: "Komutlar yalnızca adıyla istenince çalıştırılabilir."))
    }

    private static func run(_ command: CustomCommand) async -> String {
        // Without a shell "~" would stay literal; it is the only shell convenience given.
        let words = command.arguments.map { $0.hasPrefix("~") ? NSString(string: $0).expandingTildeInPath : $0 }
        guard let program = words.first, let executable = ExecutableLookup.path(of: program) else {
            return ToolReply.failure(String(localized: "'\(command.name)' komutunun programı bulunamadı: \(command.arguments.first ?? "")"))
        }
        do {
            let output = try await ProcessRunner.run(executable, Array(words.dropFirst()), timeout: timeout)
            guard output.status == 0 else {
                Log.tools.error("Custom command \(command.name, privacy: .private) failed (\(output.status)): \(output.standardError, privacy: .private)")
                return ToolReply.failure(String(localized: "'\(command.name)' komutu hata verdi (çıkış kodu \(Int(output.status))) ya da \(Int(timeout.components.seconds)) saniyede bitmedi."))
            }
            let printed = output.standardOutput.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !printed.isEmpty else { return String(localized: "'\(command.name)' komutu çalıştı.") }
            return String(localized: "'\(command.name)' komutu çalıştı. Çıktısı: \(String(printed.prefix(outputCharacters)))")
        } catch {
            return ToolReply.failure(String(localized: "'\(command.name)' komutu çalıştırılamadı: \(error.localizedDescription)"))
        }
    }
}

/// Where a program named without a path lives. Apps started from the Dock get a minimal PATH, so the places
/// Homebrew and other installers use are searched too.
enum ExecutableLookup {
    private static let extraFolders = ["/opt/homebrew/bin", "/opt/homebrew/sbin", "/usr/local/bin", "/usr/local/sbin"]

    static func path(of program: String) -> String? {
        let manager = FileManager.default
        if program.contains("/") {
            return manager.isExecutableFile(atPath: program) ? program : nil
        }
        let path = ProcessInfo.processInfo.environment["PATH"]?.split(separator: ":").map(String.init) ?? []
        var folders = path + extraFolders + ["/usr/bin", "/bin", "/usr/sbin", "/sbin"]
        folders.append(NSString(string: "~/.local/bin").expandingTildeInPath)
        return folders.lazy.map { "\($0)/\(program)" }.first { manager.isExecutableFile(atPath: $0) }
    }
}
