import CoreGraphics
import Vision

/// Text in an image, read on this Mac with Vision in Turkish and English; for the screen and scanned PDFs.
enum TextRecognition {
    static func text(in image: CGImage) async throws -> String {
        do {
            return try await recognize(image)
        } catch where !Task.isCancelled {
            // Vision cancelled the first request right after Screen Recording was granted; the next one worked.
            Log.tools.info("Text recognition failed once, trying again: \(error.localizedDescription, privacy: .public)")
            return try await recognize(image)
        }
    }

    private static func recognize(_ image: CGImage) async throws -> String {
        var request = RecognizeTextRequest()
        request.recognitionLevel = .accurate
        request.usesLanguageCorrection = true
        let wanted = [Locale.Language(identifier: "tr-TR"), Locale.Language(identifier: "en-US")]
        request.recognitionLanguages = wanted.filter { request.supportedRecognitionLanguages.contains($0) }
        let observations = try await request.perform(on: image)
        return observations.compactMap { $0.topCandidates(1).first?.string }.joined(separator: "\n")
    }
}
