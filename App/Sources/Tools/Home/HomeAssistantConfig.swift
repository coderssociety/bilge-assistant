import AsistanCore
import Foundation
import Observation

/// The Home Assistant server the user set up in Settings: its address in UserDefaults, its long-lived access token in
/// the Keychain. The token is read only when a request is sent and is never logged.
@MainActor
@Observable
final class HomeAssistantConfig {
    private static let addressKey = "homeAssistantAddress"
    private static let tokenAccount = "homeAssistantToken"

    private let defaults: UserDefaults
    var address: String { didSet { defaults.set(address, forKey: Self.addressKey) } }
    private(set) var hasToken: Bool

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        address = defaults.string(forKey: Self.addressKey) ?? ""
        hasToken = Keychain.contains(Self.tokenAccount)
    }

    var baseURL: URL? { HomeAssistantAPI.baseAddress(address) }

    /// Smart-home commands go to Home Assistant only once both are set.
    var isConfigured: Bool { baseURL != nil && hasToken }

    func saveToken(_ token: String) throws {
        let trimmed = token.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        try Keychain.save(trimmed, for: Self.tokenAccount)
        hasToken = true
    }

    func removeToken() throws {
        try Keychain.delete(Self.tokenAccount)
        hasToken = false
    }

    /// The address and token for one request.
    func connection() throws -> HomeAssistantClient.Connection {
        guard let base = baseURL else { throw HomeAssistantError.invalidAddress }
        guard let token = try Keychain.read(Self.tokenAccount), !token.isEmpty else { throw HomeAssistantError.noToken }
        return HomeAssistantClient.Connection(base: base, token: token)
    }
}
