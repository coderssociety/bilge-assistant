import AsistanCore
import Foundation
import FoundationModels

/// Bluetooth power through IOBluetooth's preference functions (what blueutil uses). They are not in
/// the public headers, so they are looked up with dlsym; nil or false means they are unavailable.
enum BluetoothControl {
    private typealias GetPowerState = @convention(c) () -> Int32
    private typealias SetPowerState = @convention(c) (Int32) -> Void
    private static let framework = "/System/Library/Frameworks/IOBluetooth.framework/IOBluetooth"
    private static let settleTimeout: Duration = .seconds(3)
    private static let pollInterval: Duration = .milliseconds(250)

    static func isPoweredOn() -> Bool? {
        guard let handle = dlopen(framework, RTLD_LAZY),
              let symbol = dlsym(handle, "IOBluetoothPreferenceGetControllerPowerState") else { return nil }
        return unsafeBitCast(symbol, to: GetPowerState.self)() != 0
    }

    /// The controller takes a moment to switch; waits until it reports the new state.
    static func setPower(_ on: Bool) async -> Bool {
        guard let handle = dlopen(framework, RTLD_LAZY),
              let symbol = dlsym(handle, "IOBluetoothPreferenceSetControllerPowerState") else { return false }
        unsafeBitCast(symbol, to: SetPowerState.self)(on ? 1 : 0)
        let deadline = ContinuousClock.now + settleTimeout
        while ContinuousClock.now < deadline {
            if isPoweredOn() == on { return true }
            try? await Task.sleep(for: pollInterval)
        }
        return isPoweredOn() == on
    }
}

struct BluetoothTool: AssistantTool {
    let name = "setBluetooth"
    let description = "Bluetooth'u açar, kapatır ya da açık olup olmadığını söyler."

    @Generable
    enum Action {
        case on, off, status
    }

    @Generable
    struct Arguments {
        @Guide(description: "Açmak için on, kapatmak için off, açık mı diye sormak için status")
        var action: Action
    }

    func refine(_ arguments: Arguments, command: String) -> Arguments {
        switch MacControlRequest.bluetooth(command, language: AppLanguage.current) {
        case .on: Arguments(action: .on)
        case .off: Arguments(action: .off)
        case .status: Arguments(action: .status)
        case nil: arguments
        }
    }

    /// A Bluetooth keyboard or mouse may be the only one, so turning it off always asks first.
    func makeCall(_ arguments: Arguments) async -> PreparedToolCall {
        let turningOff = arguments.action == .off
        return PreparedToolCall(
            toolName: name,
            argumentsDescription: String(describing: arguments),
            risk: turningOff ? .needsConfirmation : .safe,
            confirmationQuestion: turningOff
                ? String(localized: "Bluetooth'u kapatırsam Bluetooth klavye, fare ve kulaklıkların bağlantısı kesilir. Kapatayım mı?")
                : nil,
            execute: { try await call(arguments: arguments) })
    }

    func call(arguments: Arguments) async throws -> String {
        guard let isOn = BluetoothControl.isPoweredOn() else {
            return ToolReply.failure(String(localized: "Bluetooth'u bu macOS sürümünde kontrol edemiyorum."))
        }
        switch arguments.action {
        case .status:
            return isOn ? String(localized: "Bluetooth açık.") : String(localized: "Bluetooth kapalı.")
        case .on where isOn:
            return String(localized: "Bluetooth zaten açık.")
        case .off where !isOn:
            return String(localized: "Bluetooth zaten kapalı.")
        case .on, .off:
            let turnOn = arguments.action == .on
            guard await BluetoothControl.setPower(turnOn) else {
                return ToolReply.failure(String(localized: "Bluetooth değişmedi. Sistem Ayarları > Gizlilik ve Güvenlik > Bluetooth'ta Bilge'ye izin verilmiş olmalı."))
            }
            return turnOn ? String(localized: "Bluetooth açıldı.") : String(localized: "Bluetooth kapatıldı.")
        }
    }
}
