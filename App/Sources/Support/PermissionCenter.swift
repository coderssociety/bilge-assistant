@preconcurrency import AVFoundation
import AppKit
import EventKit
import Speech

/// Current state of every privacy permission the assistant uses, and where to change it.
enum Permission: String, CaseIterable, Identifiable {
    case microphone
    case speechRecognition
    case calendar
    case reminders
    case automation

    enum State {
        case granted
        case denied
        case notAsked
        /// macOS offers no way to read it without prompting; it is asked per app on first use.
        case askedOnUse
    }

    var id: String { rawValue }

    var title: String {
        switch self {
        case .microphone: "Mikrofon"
        case .speechRecognition: "Konuşma Tanıma"
        case .calendar: "Takvim"
        case .reminders: "Anımsatıcılar"
        case .automation: "Otomasyon (Müzik, Notlar, Sistem Olayları)"
        }
    }

    var purpose: String {
        switch self {
        case .microphone: "Uyandırma kelimesini ve komutlarını duymak için. Zorunlu."
        case .speechRecognition: "Türkçe konuşmayı cihaz üzerinde yazıya dökmek için. Zorunlu."
        case .calendar: "Takvimi okumak ve onayınla etkinlik eklemek için."
        case .reminders: "Anımsatıcıları okumak ve onayınla eklemek için."
        case .automation: "Müzik kontrolü, not oluşturma ve karanlık mod için. İlk kullanımda sorulur."
        }
    }

    var isRequired: Bool { self == .microphone || self == .speechRecognition }

    var state: State {
        switch self {
        case .microphone:
            switch AVCaptureDevice.authorizationStatus(for: .audio) {
            case .authorized: .granted
            case .notDetermined: .notAsked
            default: .denied
            }
        case .speechRecognition:
            switch SFSpeechRecognizer.authorizationStatus() {
            case .authorized: .granted
            case .notDetermined: .notAsked
            default: .denied
            }
        case .calendar: Self.eventState(EKEventStore.authorizationStatus(for: .event))
        case .reminders: Self.eventState(EKEventStore.authorizationStatus(for: .reminder))
        case .automation: .askedOnUse
        }
    }

    @MainActor
    func request() async {
        switch self {
        case .microphone:
            _ = await AVCaptureDevice.requestAccess(for: .audio)
        case .speechRecognition:
            _ = await withCheckedContinuation { continuation in
                SFSpeechRecognizer.requestAuthorization { continuation.resume(returning: $0) }
            }
        case .calendar:
            _ = try? await EKEventStore().requestFullAccessToEvents()
        case .reminders:
            _ = try? await EKEventStore().requestFullAccessToReminders()
        case .automation:
            openSystemSettings()
        }
    }

    func openSystemSettings() {
        let anchor = switch self {
        case .microphone: "Privacy_Microphone"
        case .speechRecognition: "Privacy_SpeechRecognition"
        case .calendar: "Privacy_Calendars"
        case .reminders: "Privacy_Reminders"
        case .automation: "Privacy_Automation"
        }
        guard let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?\(anchor)") else { return }
        NSWorkspace.shared.open(url)
    }

    private static func eventState(_ status: EKAuthorizationStatus) -> State {
        switch status {
        case .fullAccess: .granted
        case .notDetermined: .notAsked
        default: .denied
        }
    }
}
