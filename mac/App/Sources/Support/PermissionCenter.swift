@preconcurrency import AVFoundation
import AppKit
import ApplicationServices
import Contacts
import EventKit
import Speech

/// Current state of every privacy permission the assistant uses, and where to change it.
enum Permission: String, CaseIterable, Identifiable {
    case microphone
    case speechRecognition
    case calendar
    case reminders
    case screenRecording
    case contacts
    case accessibility
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
        case .microphone: String(localized: "Mikrofon")
        case .speechRecognition: String(localized: "Konuşma Tanıma")
        case .calendar: String(localized: "Takvim")
        case .reminders: String(localized: "Anımsatıcılar")
        case .screenRecording: String(localized: "Ekran Kaydı")
        case .contacts: String(localized: "Kişiler")
        case .accessibility: String(localized: "Erişilebilirlik")
        case .automation: String(localized: "Otomasyon (Müzik, Notlar, Sistem Olayları)")
        }
    }

    var purpose: String {
        switch self {
        case .microphone: String(localized: "Uyandırma kelimesini ve komutlarını duymak için. Zorunlu.")
        case .speechRecognition: String(localized: "Türkçe konuşmayı cihaz üzerinde yazıya dökmek için. Zorunlu.")
        case .calendar: String(localized: "Takvimi okumak ve onayınla etkinlik eklemek için.")
        case .reminders: String(localized: "Anımsatıcıları okumak ve onayınla eklemek için.")
        case .screenRecording: String(localized: "“Ekranda ne yazıyor?” için. Görüntü kaydedilmez, sadece okunur.")
        case .contacts: String(localized: "Birinin numarasını ya da e-postasını bulmak ve onayınla mesaj göndermek için.")
        case .accessibility: String(localized: "Dikte edileni yazmak, seçili metni okumak ve pencereleri düzenlemek için.")
        case .automation: String(localized: "Müzik kontrolü, not oluşturma ve karanlık mod için. İlk kullanımda sorulur.")
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
        case .screenRecording: CGPreflightScreenCaptureAccess() ? .granted : .notAsked
        case .contacts:
            switch CNContactStore.authorizationStatus(for: .contacts) {
            case .authorized, .limited: .granted
            case .notDetermined: .notAsked
            default: .denied
            }
        case .accessibility: AXIsProcessTrusted() ? .granted : .notAsked
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
        case .screenRecording:
            CGRequestScreenCaptureAccess()
        case .contacts:
            _ = try? await CNContactStore().requestAccess(for: .contacts)
        case .accessibility:
            _ = AXIsProcessTrustedWithOptions(["AXTrustedCheckOptionPrompt": true] as CFDictionary)
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
        case .screenRecording: "Privacy_ScreenCapture"
        case .contacts: "Privacy_Contacts"
        case .accessibility: "Privacy_Accessibility"
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
