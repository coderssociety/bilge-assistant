import Foundation
import Observation

/// Keeps the listening shortcut registered with the system to match the settings.
@MainActor
@Observable
final class ListeningShortcut {
    /// Why the chosen shortcut is not working, for the settings window.
    private(set) var problem: String?
    @ObservationIgnored private var hotKey: GlobalHotKey?
    @ObservationIgnored private let pressed: @MainActor () -> Void
    @ObservationIgnored private let failed: @MainActor () -> Void

    /// `failed` runs when the shortcut can't be registered, so the wake word can be switched back on: without
    /// both the assistant could not be called at all.
    init(pressed: @escaping @MainActor () -> Void, failed: @escaping @MainActor () -> Void) {
        self.pressed = pressed
        self.failed = failed
    }

    func apply(_ combination: KeyCombination?) {
        hotKey?.unregister()
        hotKey = nil
        problem = nil
        guard let combination else { return }
        do throws(GlobalHotKey.Failure) {
            hotKey = try GlobalHotKey(combination, pressed: pressed)
        } catch {
            switch error {
            case .taken:
                problem = String(localized: "\(combination.display) başka bir uygulamada kullanılıyor; başka bir kısayol seç.")
            case let .failed(status):
                Log.wake.error("Could not register the shortcut: \(status)")
                problem = String(localized: "Kısayol kaydedilemedi (\(status)).")
            }
            failed()
        }
    }
}
