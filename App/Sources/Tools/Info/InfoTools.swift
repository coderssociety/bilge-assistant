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
        let locale = Locale(identifier: "tr_TR")
        let time = Date.now.formatted(.dateTime.hour(.twoDigits(amPM: .omitted)).minute().locale(locale))
        let day = Date.now.formatted(.dateTime.day().month(.wide).year().weekday(.wide).locale(locale))
        return "Saat \(time). Bugün \(day)."
    }
}

struct CalculatorTool: AssistantTool {
    let name = "calculate"
    let description = "Aritmetik hesap yapar. Yüzde hesabını çarpma/bölmeye çevir: '125'in yüzde 18'i' → '125 * 18 / 100'."

    @Generable
    struct Arguments {
        @Guide(description: "Sadece sayılar ve + - * / % ^ ( ) içeren ifade")
        var expression: String
    }

    func call(arguments: Arguments) async throws -> String {
        do {
            let value = try ArithmeticEvaluator.evaluate(arguments.expression)
            return "Sonuç \(ArithmeticEvaluator.display(value))."
        } catch {
            return ToolReply.failure("'\(arguments.expression)' hesaplanamadı.")
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
        else { return "Bu Mac'te pil yok, prize bağlı çalışıyor." }
        let charging = details[kIOPSIsChargingKey] as? Bool ?? false
        let onPower = (details[kIOPSPowerSourceStateKey] as? String) == kIOPSACPowerValue
        let state = charging ? "şarj oluyor" : onPower ? "prize bağlı" : "pilden çalışıyor"
        return "Pil yüzde \(capacity), \(state)."
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
            return "Panoda metin yok."
        }
        let clipped = text.count > Self.maxCharacters ? String(text.prefix(Self.maxCharacters)) + "…" : text
        return "Panodaki metin: \(clipped)"
    }
}
