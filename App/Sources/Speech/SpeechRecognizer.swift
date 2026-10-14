import AsistanCore
import Foundation

enum RecognizerEngine: String, CaseIterable, Codable, Sendable {
    case whisper
    case appleDictation

    var displayName: String {
        switch self {
        case .whisper: "Whisper large-v3 turbo"
        case .appleDictation: "Apple Dikte"
        }
    }
}

/// Transcribes one complete utterance of 16 kHz mono Float32 audio in the assistant's language.
protocol SpeechRecognizer: Actor {
    nonisolated var engine: RecognizerEngine { get }
    func prepare() async throws
    func transcribe(_ samples: [Float]) async throws -> String
}

enum RecognizerError: LocalizedError {
    case notPrepared
    case localeUnsupported
    case permissionDenied
    case audioFormatUnavailable

    var errorDescription: String? {
        switch self {
        case .notPrepared: "Konuşma tanıma modeli henüz yüklenmedi."
        case .localeUnsupported: "Bu Mac'te seçili dilde dikte desteklenmiyor."
        case .permissionDenied: "Konuşma tanıma izni verilmedi. Sistem Ayarları > Gizlilik ve Güvenlik > Konuşma Tanıma."
        case .audioFormatUnavailable: "Konuşma tanıma için uygun ses biçimi bulunamadı."
        }
    }
}

enum RecognizerFactory {
    static func make(_ engine: RecognizerEngine, language: AssistantLanguage) -> any SpeechRecognizer {
        switch engine {
        case .whisper: WhisperKitRecognizer(language: language)
        case .appleDictation: AppleDictationRecognizer(language: language)
        }
    }

    /// Apple dictation is instant and small for Turkish; in English only Whisper reliably hears "Bilge".
    static func defaultEngine(for language: AssistantLanguage) -> RecognizerEngine {
        language == .english ? .whisper : .appleDictation
    }
}
