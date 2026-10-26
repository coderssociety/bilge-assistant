import AppKit
import AsistanCore
import FoundationModels

/// The display brightness through the private DisplayServices framework, which the brightness keys and
/// Control Center use. It is loaded with dlopen, so a macOS without it falls back to brightness keys.
@MainActor
enum DisplayBrightness {
    private typealias GetBrightness = @convention(c) (CGDirectDisplayID, UnsafeMutablePointer<Float>) -> Int32
    private typealias SetBrightness = @convention(c) (CGDirectDisplayID, Float) -> Int32
    private typealias CanChangeBrightness = @convention(c) (CGDirectDisplayID) -> Bool
    private static let framework = "/System/Library/PrivateFrameworks/DisplayServices.framework/DisplayServices"
    private static let maxDisplays: UInt32 = 16
    /// One brightness key press moves the level by a sixteenth.
    private static let keySteps = 16

    enum Outcome {
        case level(Int)
        case pressedKeys
        case notControllable
        case failed
    }

    static func change(by delta: Float?, to target: Float?) throws -> Outcome {
        guard let handle = dlopen(framework, RTLD_LAZY),
              let getSymbol = dlsym(handle, "DisplayServicesGetBrightness"),
              let setSymbol = dlsym(handle, "DisplayServicesSetBrightness")
        else {
            Log.tools.error("DisplayServices unavailable; using brightness keys")
            return try pressKeys(delta: delta, target: target)
        }
        let get = unsafeBitCast(getSymbol, to: GetBrightness.self)
        let set = unsafeBitCast(setSymbol, to: SetBrightness.self)
        let canChange = dlsym(handle, "DisplayServicesCanChangeBrightness").map { unsafeBitCast($0, to: CanChangeBrightness.self) }
        guard let display = onlineDisplays().first(where: { CGDisplayIsBuiltin($0) != 0 })
            ?? onlineDisplays().first(where: { canChange?($0) == true })
        else { return .notControllable }
        var current: Float = 0
        guard get(display, &current) == 0 else { return .notControllable }
        let level = min(max(target ?? current + (delta ?? 0), 0), 1)
        guard set(display, level) == 0 else { return .failed }
        var applied: Float = level
        _ = get(display, &applied)
        return .level(Int((applied * 100).rounded()))
    }

    /// Brightness keys reach only the built-in display; a level is set by going all the way down first.
    private static func pressKeys(delta: Float?, target: Float?) throws -> Outcome {
        guard onlineDisplays().contains(where: { CGDisplayIsBuiltin($0) != 0 }) else { return .notControllable }
        let step = 1 / Float(keySteps)
        if let target {
            for _ in 0..<keySteps { try SystemKeys.press(NX_KEYTYPE_BRIGHTNESS_DOWN) }
            for _ in 0..<Int((target / step).rounded()) { try SystemKeys.press(NX_KEYTYPE_BRIGHTNESS_UP) }
        } else if let delta {
            let key = delta > 0 ? NX_KEYTYPE_BRIGHTNESS_UP : NX_KEYTYPE_BRIGHTNESS_DOWN
            for _ in 0..<max(1, Int((abs(delta) / step).rounded())) { try SystemKeys.press(key) }
        }
        return .pressedKeys
    }

    private static func onlineDisplays() -> [CGDirectDisplayID] {
        var displays = [CGDirectDisplayID](repeating: 0, count: Int(maxDisplays))
        var count: UInt32 = 0
        guard CGGetOnlineDisplayList(maxDisplays, &displays, &count) == .success else { return [] }
        return Array(displays.prefix(Int(count)))
    }
}

struct BrightnessTool: AssistantTool {
    let name = "setBrightness"
    let description = "Ekran parlaklığını artırır, azaltır ya da yüzde olarak ayarlar."
    private static let step = 10

    @Generable
    enum Action {
        case set, increase, decrease
    }

    @Generable
    struct Arguments {
        var action: Action
        @Guide(description: "Sadece 'set' için hedef yüzde", .range(0...100))
        var level: Int?
        @Guide(description: "Sadece 'increase'/'decrease' için ne kadar: 'yüzde 20 artır' → 20. Söylenmediyse boş bırak.", .range(1...100))
        var amount: Int?
    }

    func refine(_ arguments: Arguments, command: String) -> Arguments {
        switch MacControlRequest.brightness(command, language: AppLanguage.current) {
        case let .up(amount): Arguments(action: .increase, level: nil, amount: amount)
        case let .down(amount): Arguments(action: .decrease, level: nil, amount: amount)
        case let .set(level): Arguments(action: .set, level: level, amount: nil)
        case nil: arguments
        }
    }

    func call(arguments: Arguments) async throws -> String {
        let amount = Float(arguments.amount ?? Self.step) / 100
        let (delta, target): (Float?, Float?) = switch arguments.action {
        case .set: (nil, arguments.level.map { Float($0) / 100 })
        case .increase: (amount, nil)
        case .decrease: (-amount, nil)
        }
        guard delta != nil || target != nil else {
            return ToolReply.failure(String(localized: "Hedef parlaklık belirtilmedi."))
        }
        do {
            switch try await MainActor.run(body: { try DisplayBrightness.change(by: delta, to: target) }) {
            case let .level(percent): return String(localized: "Parlaklık yüzde \(percent).")
            case .pressedKeys: return String(localized: "Parlaklığı ayarladım.")
            case .notControllable:
                return ToolReply.failure(String(localized: "Bu ekranın parlaklığını Mac'ten değiştiremiyorum; harici ekranlarda ekranın kendi düğmelerini kullanman gerekiyor."))
            case .failed: return ToolReply.failure(String(localized: "Parlaklık değiştirilemedi."))
            }
        } catch {
            return ToolReply.failure(error)
        }
    }
}
