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
    let description = "Pil doluluk yüzdesini, şarj durumunu ve pilin ne kadar yeteceğini ya da ne zaman dolacağını verir."

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
        let summary = String(localized: "Pil yüzde \(capacity), \(state).")
        // macOS reports -1 minutes while it is still estimating.
        if charging, let minutes = details[kIOPSTimeToFullChargeKey] as? Int, minutes > 0 {
            return summary + " " + String(localized: "Yaklaşık \(Duration.seconds(minutes * 60).spoken) içinde dolar.")
        }
        if !onPower, let minutes = details[kIOPSTimeToEmptyKey] as? Int, minutes > 0 {
            return summary + " " + String(localized: "Yaklaşık \(Duration.seconds(minutes * 60).spoken) daha yeter.")
        }
        return summary
    }
}

/// "Panoda ne var" reads the copied text out; "panodakini özetle/çevir" hands it to the tool-less session,
/// like the selection, since it may come from anywhere.
struct ClipboardReadTool: AssistantTool {
    let name = "readClipboard"
    let description = "Panodaki (kopyalanan) metni okur; özetler, çevirir ya da açıklar."
    private static let spokenCharacters = 1500
    private static let materialCharacters = 6000

    @Generable
    struct Arguments {
        @Guide(description: "Panodaki metinle ne yapılacağı, örn. 'oku', 'özetle', 'İngilizceye çevir'")
        var request: String?
    }

    func arguments(fromCommand command: String) -> Arguments? {
        Arguments(request: command)
    }

    func makeCall(_ arguments: Arguments) async -> PreparedToolCall {
        PreparedToolCall(toolName: name, argumentsDescription: String(describing: arguments), risk: risk,
                         confirmationQuestion: nil, answersWithLanguageModel: Self.answersWithLanguageModel(arguments),
                         execute: { try await call(arguments: arguments) })
    }

    func call(arguments: Arguments) async throws -> String {
        let text = await MainActor.run { NSPasteboard.general.string(forType: .string) }
        let viaModel = Self.answersWithLanguageModel(arguments)
        guard let text, !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            let empty = String(localized: "Panoda metin yok.")
            return viaModel ? ToolReply.failure(empty) : empty
        }
        if viaModel { return String(text.prefix(Self.materialCharacters)) }
        let clipped = text.count > Self.spokenCharacters ? String(text.prefix(Self.spokenCharacters)) + "…" : text
        return String(localized: "Panodaki metin: \(clipped)")
    }

    private static func answersWithLanguageModel(_ arguments: Arguments) -> Bool {
        ReadingRequest.asksBeyondReading(arguments.request ?? "", language: AppLanguage.current)
    }
}
