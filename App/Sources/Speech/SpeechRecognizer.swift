import AsistanCore
import Foundation

enum RecognizerEngine: String, CaseIterable, Codable, Sendable {
    case whisper
    case appleDictation

    var displayName: String {
        switch self {
        case .whisper: "Whisper large-v3 turbo"
        case .appleDictation: String(localized: "Apple Dikte")
        }
    }
}

/// What was said and which language it was in (ISO 639-1).
struct DetectedSpeech: Sendable, Equatable {
    let text: String
    let language: String
}

/// Transcribes one complete utterance of 16 kHz mono Float32 audio in the assistant's language.
protocol SpeechRecognizer: Actor {
    nonisolated var engine: RecognizerEngine { get }
    func prepare() async throws
    func transcribe(_ samples: [Float]) async throws -> String
    /// Transcribes speech in whichever of `languages` it is in; nil when the engine cannot tell languages apart.
    func transcribe(_ samples: [Float], detectingAmong languages: [String]) async throws -> DetectedSpeech?
}

extension SpeechRecognizer {
    func transcribe(_ samples: [Float], detectingAmong languages: [String]) async throws -> DetectedSpeech? {
        nil
    }
}

enum RecognizerError: LocalizedError {
    case notPrepared
    case localeUnsupported
    case permissionDenied
    case audioFormatUnavailable

    var errorDescription: String? {
        switch self {
        case .notPrepared: String(localized: "Konuşma tanıma modeli henüz yüklenmedi.")
        case .localeUnsupported: String(localized: "Bu Mac'te seçili dilde dikte desteklenmiyor.")
        case .permissionDenied:
            String(localized: "Konuşma tanıma izni verilmedi. Sistem Ayarları > Gizlilik ve Güvenlik > Konuşma Tanıma.")
        case .audioFormatUnavailable: String(localized: "Konuşma tanıma için uygun ses biçimi bulunamadı.")
        }
    }
}

enum RecognizerFactory {
    /// `guarded`: behind GuardedRecognizer, as the assistant uses it; the ASR benchmark measures the engine alone.
    static func make(_ engine: RecognizerEngine, language: AssistantLanguage, guarded: Bool = true) -> any SpeechRecognizer {
        let recognizer: any SpeechRecognizer = switch engine {
        case .whisper: WhisperKitRecognizer(language: language)
        case .appleDictation: AppleDictationRecognizer(language: language)
        }
        return guarded ? GuardedRecognizer(recognizer) : recognizer
    }

    /// Apple dictation is instant and small for Turkish; in English only Whisper reliably hears "Bilge".
    static func defaultEngine(for language: AssistantLanguage) -> RecognizerEngine {
        language == .english ? .whisper : .appleDictation
    }
}
