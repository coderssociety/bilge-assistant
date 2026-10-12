import Foundation

enum RecognizerEngine: String, CaseIterable, Codable, Sendable {
    case whisper
    case appleDictation

    var displayName: String {
        switch self {
        case .whisper: "Whisper large-v3 turbo"
        case .appleDictation: "Apple Dikte (tr_TR)"
        }
    }
}

/// Transcribes one complete utterance of 16 kHz mono Float32 audio into Turkish text.
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
        case .localeUnsupported: "Bu Mac'te Türkçe dikte desteklenmiyor."
        case .permissionDenied: "Konuşma tanıma izni verilmedi. Sistem Ayarları > Gizlilik ve Güvenlik > Konuşma Tanıma."
        case .audioFormatUnavailable: "Konuşma tanıma için uygun ses biçimi bulunamadı."
        }
    }
}

enum RecognizerFactory {
    static func make(_ engine: RecognizerEngine) -> any SpeechRecognizer {
        switch engine {
        case .whisper: WhisperKitRecognizer()
        case .appleDictation: AppleDictationRecognizer()
        }
    }
}
