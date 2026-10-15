import AppKit
import AsistanCore
import FoundationModels
import IOKit.ps

struct DateTimeTool: AssistantTool {
    let name = "currentDateTime"
    let description = "Şu anki tarihi, saati ve haftanın gününü verir."

    @Generable
    struct Arguments {}

    func emptyArguments() -> Arguments? { Arguments() }

    func call(arguments: Arguments) async throws -> String {
        let locale = AppLanguage.locale
        let time = Date.now.formatted(.dateTime.hour(.twoDigits(amPM: .omitted)).minute(.twoDigits).locale(locale))
        let day = Date.now.formatted(.dateTime.day().month(.wide).year().weekday(.wide).locale(locale))
        return String(localized: "Saat \(time). Bugün \(day).")
    }
}

struct CalculatorTool: AssistantTool {
    let name = "calculate"
    let description = "Aritmetik hesap yapar. Yüzde hesabını çarpma/bölmeye çevir: '125'in yüzde 18'i' → '125 * 18 / 100'."
    var language = AssistantLanguage.turkish

    @Generable
    struct Arguments {
        @Guide(description: "Sadece sayılar ve + - * / % ^ ( ) içeren ifade")
        var expression: String
    }

    /// Common phrasings are parsed exactly; a model-written expression is only trusted when every
    /// number in it was actually said (it once computed "125 * 18 / 100" for a bare "Evet").
    func refine(_ arguments: Arguments, command: String) -> Arguments {
        var refined = arguments
        let parsed = language == .english
            ? EnglishArithmeticParser.expression(from: command) : TurkishArithmeticParser.expression(from: command)
        let grounded = language == .english
            ? EnglishArithmeticParser.isGrounded(arguments.expression, in: command)
            : TurkishArithmeticParser.isGrounded(arguments.expression, in: command)
        if let parsed {
            refined.expression = parsed
        } else if !grounded {
            refined.expression = ""
        }
        return refined
    }

    func prefersConversation(for arguments: Arguments) -> Bool {
        arguments.expression.isEmpty
    }

    func call(arguments: Arguments) async throws -> String {
        guard !arguments.expression.isEmpty else {
            return ToolReply.failure(String(localized: "Hesabı tam anlayamadım, sayılarla tekrar söyler misin?"))
        }
        do {
            let value = try ArithmeticEvaluator.evaluate(arguments.expression)
            return String(localized: "Sonuç \(ArithmeticEvaluator.display(value, language: language)).")
        } catch {
            return ToolReply.failure(String(localized: "'\(arguments.expression)' hesaplanamadı."))
        }
    }
}

struct BatteryTool: AssistantTool {
    let name = "batteryStatus"
    let description = "Pil doluluk yüzdesini ve şarj durumunu verir."

    @Generable
    struct Arguments {}

    func emptyArguments() -> Arguments? { Arguments() }

    func call(arguments: Arguments) async throws -> String {
        guard let info = IOPSCopyPowerSourcesInfo()?.takeRetainedValue(),
              let sources = IOPSCopyPowerSourcesList(info)?.takeRetainedValue() as? [CFTypeRef],
              let source = sources.first,
              let details = IOPSGetPowerSourceDescription(info, source)?.takeUnretainedValue() as? [String: Any],
              let capacity = details[kIOPSCurrentCapacityKey] as? Int
        else { return String(localized: "Bu Mac'te pil yok, prize bağlı çalışıyor.") }
        let charging = details[kIOPSIsChargingKey] as? Bool ?? false
        let onPower = (details[kIOPSPowerSourceStateKey] as? String) == kIOPSACPowerValue
        let state = charging
            ? String(localized: "şarj oluyor")
            : onPower ? String(localized: "prize bağlı") : String(localized: "pilden çalışıyor")
        return String(localized: "Pil yüzde \(capacity), \(state).")
    }
}

struct ClipboardReadTool: AssistantTool {
    let name = "readClipboard"
    let description = "Panodaki (kopyalanan) metni okur."
    private static let maxCharacters = 1500

    @Generable
    struct Arguments {}

    func emptyArguments() -> Arguments? { Arguments() }

    func call(arguments: Arguments) async throws -> String {
        let text = await MainActor.run { NSPasteboard.general.string(forType: .string) }
        guard let text, !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            return String(localized: "Panoda metin yok.")
        }
        let clipped = text.count > Self.maxCharacters ? String(text.prefix(Self.maxCharacters)) + "…" : text
        return String(localized: "Panodaki metin: \(clipped)")
    }
}
