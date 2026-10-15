import Foundation
import FoundationModels

/// `networksetup` changes Wi-Fi power without administrator rights.
enum WiFiControl {
    private static let tool = "/usr/sbin/networksetup"

    static func device() async -> String? {
        guard let output = try? await ProcessRunner.run(tool, ["-listallhardwareports"]) else { return nil }
        let lines = output.standardOutput.split(separator: "\n").map(String.init)
        guard let index = lines.firstIndex(where: { $0.contains("Wi-Fi") || $0.contains("AirPort") }),
              index + 1 < lines.count, lines[index + 1].hasPrefix("Device: ")
        else { return nil }
        return String(lines[index + 1].dropFirst("Device: ".count))
    }

    static func isPoweredOn() async -> Bool? {
        guard let device = await device(),
              let output = try? await ProcessRunner.run(tool, ["-getairportpower", device])
        else { return nil }
        return output.standardOutput.hasSuffix("On")
    }

    static func setPower(_ on: Bool) async throws {
        guard let device = await device() else { throw WiFiError.noDevice }
        let output = try await ProcessRunner.run(tool, ["-setairportpower", device, on ? "on" : "off"])
        guard output.status == 0 else { throw WiFiError.failed(output.standardError) }
    }

    enum WiFiError: LocalizedError {
        case noDevice
        case failed(String)

        var errorDescription: String? {
            switch self {
            case .noDevice: String(localized: "Bu Mac'te Wi-Fi bulunamadı.")
            case let .failed(detail): String(localized: "Wi-Fi değiştirilemedi. \(detail)")
            }
        }
    }
}

struct WiFiTool: AssistantTool {
    let name = "setWiFi"
    let description = "Wi-Fi'ı açar ya da kapatır."

    @Generable
    enum Power {
        case on, off
    }

    @Generable
    struct Arguments {
        @Guide(description: "Açmak için on, kapatmak için off")
        var power: Power
    }

    /// Turning Wi-Fi off cuts the connection, so only that direction asks first.
    func makeCall(_ arguments: Arguments) async -> PreparedToolCall {
        let turningOff = arguments.power == .off
        return PreparedToolCall(
            toolName: name,
            argumentsDescription: String(describing: arguments),
            risk: turningOff ? .needsConfirmation : .safe,
            confirmationQuestion: turningOff
                ? String(localized: "Wi-Fi'ı kapatırsam internet bağlantın kesilir. Kapatayım mı?")
                : nil,
            execute: { try await call(arguments: arguments) })
    }

    func call(arguments: Arguments) async throws -> String {
        do {
            try await WiFiControl.setPower(arguments.power == .on)
            return arguments.power == .on ? String(localized: "Wi-Fi açıldı.") : String(localized: "Wi-Fi kapatıldı.")
        } catch {
            return ToolReply.failure(error)
        }
    }
}
