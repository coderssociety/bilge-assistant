import AsistanCore
import Foundation
import FoundationModels

/// Live edits in the Excel sheet in front: "D3'e B2 ile B1'i topla", "C5'e 1250 yaz", "D3'ü oku",
/// "geri al". Commands the rules understand never touch a language model; in Excel mode, other
/// requests about cells get a model-written formula, which is checked and read out before it is written.
struct SpreadsheetTool: RuleRoutedTool {
    let name = "spreadsheet"
    let description = "Öndeki Excel tablosunda hücreye formül ya da değer yazar, hücre okur, siler, kopyalar ve hesaplar ('D3'e B2 ile B1'i topla')."
    let session: SpreadsheetSession

    @Generable
    struct Arguments {
        @Guide(description: "Kullanıcının Excel isteği, olduğu gibi")
        var command: String
        @Guide(description: "Sonucun yazılacağı hücre, örn. 'D2'; yoksa boş bırak")
        var target: String?
        @Guide(description: "Hücreye yazılacak Excel formülü; İngilizce fonksiyon adları, ondalık ayırıcı nokta, argüman ayırıcı virgül: '=C2*1.2', '=SUM(B1:B9)'")
        var formula: String?
    }

    /// Whether the router should hand this command over without asking the model. Undo and finishing
    /// only count inside Excel mode; "geri al" means other things elsewhere.
    /// A command the rules understand is specific enough to claim even when Excel is closed; the tool
    /// then says so.
    @MainActor
    func claims(_ command: String) -> Bool {
        switch Self.command(in: command) {
        case .undo?, .finish?: return session.isActive
        case .some: return true
        case nil: return session.isActive && SpreadsheetCommand.mentionsCells(command, language: AppLanguage.current)
        }
    }

    func arguments(fromCommand command: String) -> Arguments? {
        guard Self.command(in: command) != nil else { return nil }
        return Arguments(command: command, target: nil, formula: nil)
    }

    func call(arguments: Arguments) async throws -> String {
        try await makeCall(arguments).execute()
    }

    func makeCall(_ arguments: Arguments) async -> PreparedToolCall {
        if let command = Self.command(in: arguments.command) {
            return await call(for: command)
        }
        return await modelFormulaCall(arguments)
    }

    /// Turkish number words become digits first ("bin iki yüz elli"); English is read as said, since the
    /// Turkish rules would turn "on" and "one" into 10.
    static func command(in text: String) -> SpreadsheetCommand? {
        let language = AppLanguage.current
        return SpreadsheetCommand.parse(language == .turkish ? TurkishNumberParser.digitize(text) : text, language: language)
    }

    private func call(for command: SpreadsheetCommand) async -> PreparedToolCall {
        switch command {
        case .finish:
            return safe("finish") {
                await MainActor.run { session.end() }
                return String(localized: "Excel modundan çıktım.")
            }
        case .undo:
            guard let change = await MainActor.run(body: { session.takeLastChange() }) else {
                return .unavailable(name, message: String(localized: "Geri alınacak bir değişikliğim yok."))
            }
            guard await ExcelBridge.isRunning() else { return .unavailable(name, message: String(localized: "Excel açık değil.")) }
            return safe("undo") { await undo(change) }
        default:
            break
        }
        guard await ExcelBridge.isRunning() else { return .unavailable(name, message: String(localized: "Excel açık değil.")) }
        let location: ExcelBridge.Location
        do {
            guard let found = try await ExcelBridge.activeLocation() else {
                return .unavailable(name, message: String(localized: "Excel'de açık bir tablo yok."))
            }
            location = found
        } catch {
            return .unavailable(name, message: error.localizedDescription)
        }
        switch command {
        case let .setFormula(target, formula):
            return await writing(target, at: location, description: formula) {
                try await ExcelBridge.setFormula(formula, in: target, at: location)
            }
        case let .setValue(target, value):
            return await writing(target, at: location, description: "value") {
                try await ExcelBridge.setValue(value, in: target, at: location)
            }
        case let .clear(cell):
            return await writing(cell, at: location, description: "clear", confirmsOverwrite: false) {
                try await ExcelBridge.clear(cell, at: location)
            }
        case let .copy(source, destination):
            return await writing(destination, at: location, description: "copy \(source.address)") {
                try await ExcelBridge.copy(source, to: destination, at: location)
            }
        case let .read(cell):
            return safe("read") {
                let value = try await ExcelBridge.displayedValue(of: cell, at: location)
                return value.isEmpty ? String(localized: "\(cell.address) boş.") : "\(cell.address): \(value)."
            }
        case let .evaluate(formula):
            return safe("evaluate") {
                var values: [String: [String]] = [:]
                for reference in SpreadsheetEvaluator.references(in: formula) {
                    values[reference] = try await ExcelBridge.values(of: reference, at: location)
                }
                guard let result = SpreadsheetEvaluator.evaluate(formula, values: values) else {
                    return ToolReply.failure(String(localized: "Bunu hesaplayamadım; hücrelerde sayı olmayabilir."))
                }
                return String(localized: "Sonuç \(Self.spokenNumber(result)).")
            }
        case .undo, .finish:
            return .unavailable(name, message: "")
        }
    }

    /// A write that remembers the cell's previous content for undo, asks before replacing something
    /// already there, and reads the new value back.
    private func writing(
        _ cell: CellReference, at location: ExcelBridge.Location, description: String, confirmsOverwrite: Bool = true,
        _ write: @escaping @Sendable () async throws -> Void
    ) async -> PreparedToolCall {
        let previous: String
        do {
            previous = try await ExcelBridge.formula(of: cell, at: location)
        } catch {
            return .unavailable(name, message: error.localizedDescription)
        }
        let execute: @Sendable () async throws -> String = { [session] in
            try await write()
            await MainActor.run {
                session.record(.init(location: location, cell: cell, previous: previous))
                session.begin()
            }
            let shown = try await ExcelBridge.displayedValue(of: cell, at: location)
            if Self.isExcelError(shown) {
                return String(localized: "\(cell.address) hata veriyor: \(shown). İstersen geri al de.")
            }
            return shown.isEmpty ? String(localized: "\(cell.address) boş.") : "\(cell.address): \(shown)."
        }
        guard confirmsOverwrite, !previous.isEmpty else {
            return PreparedToolCall(toolName: name, argumentsDescription: description, risk: .safe,
                                    confirmationQuestion: nil, execute: execute)
        }
        let question = String(localized: "\(cell.address) dolu, içinde \(Self.spoken(previous)) var. Üzerine yazayım mı?")
        return PreparedToolCall(toolName: name, argumentsDescription: description, risk: .needsConfirmation,
                                confirmationQuestion: question, execute: execute)
    }

    private func undo(_ change: SpreadsheetSession.Change) async -> String {
        do {
            if change.previous.isEmpty {
                try await ExcelBridge.clear(change.cell, at: change.location)
                return String(localized: "Geri aldım, \(change.cell.address) yine boş.")
            }
            try await ExcelBridge.setFormula(change.previous, in: change.cell, at: change.location)
            let shown = try await ExcelBridge.displayedValue(of: change.cell, at: change.location)
            return String(localized: "Geri aldım, \(change.cell.address): \(shown).")
        } catch {
            return ToolReply.failure(error)
        }
    }

    /// The model's formula for a request no rule understood, written only after the user hears it.
    private func modelFormulaCall(_ arguments: Arguments) async -> PreparedToolCall {
        guard let target = arguments.target.flatMap({ CellReference($0.trimmingCharacters(in: .whitespaces)) }),
              let formula = arguments.formula?.trimmingCharacters(in: .whitespaces), SpreadsheetFormula.isSafe(formula)
        else {
            return .unavailable(name, message: String(
                localized: "Bunu tabloda nasıl yapacağımı anlayamadım. Örneğin 'D3'e B2 ile B1'i topla' diyebilirsin."))
        }
        do {
            guard let location = try await ExcelBridge.activeLocation() else {
                return .unavailable(name, message: String(localized: "Excel'de açık bir tablo yok."))
            }
            let call = await writing(target, at: location, description: formula, confirmsOverwrite: false) {
                try await ExcelBridge.setFormula(formula, in: target, at: location)
            }
            return call.requiringConfirmation(
                String(localized: "\(target.address) hücresine \(Self.spoken(formula)) formülünü yazayım mı?"))
        } catch {
            return .unavailable(name, message: error.localizedDescription)
        }
    }

    private func safe(_ description: String, _ execute: @escaping @Sendable () async throws -> String) -> PreparedToolCall {
        PreparedToolCall(toolName: name, argumentsDescription: description, risk: .safe, confirmationQuestion: nil, execute: execute)
    }

    private static let maxSpokenContent = 60

    /// Formulas read aloud: "=B2+B1" → "eşittir B2 artı B1".
    private static func spoken(_ content: String) -> String {
        let short = content.count <= maxSpokenContent ? content : String(content.prefix(maxSpokenContent)) + "…"
        guard short.hasPrefix("=") else { return "'\(short)'" }
        let words: [(String, String)] = [
            ("=", String(localized: "eşittir ")), ("+", String(localized: " artı ")), ("-", String(localized: " eksi ")),
            ("*", String(localized: " çarpı ")), ("/", String(localized: " bölü ")), (":", String(localized: " ile ")),
        ]
        let decimals = AppLanguage.current == .turkish ? short.replacing(/(\d)\.(\d)/) { "\($0.1),\($0.2)" } : short
        return words.reduce(decimals) { $0.replacingOccurrences(of: $1.0, with: $1.1) }
    }

    /// Excel shows errors as "#DIV/0!", "#NAME?" and the like.
    private static func isExcelError(_ value: String) -> Bool {
        value.hasPrefix("#")
    }

    private static func spokenNumber(_ value: Double) -> String {
        value.formatted(.number.precision(.fractionLength(0...2)).locale(AppLanguage.locale))
    }
}
