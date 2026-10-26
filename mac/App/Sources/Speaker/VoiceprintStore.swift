import AsistanCore
import Foundation
import Observation

/// The enrolled voice, in ~/Library/Application Support/Asistan/voiceprint.json (readable by the user
/// alone). It holds speaker embeddings, not recordings: no audio is kept.
@MainActor
@Observable
final class VoiceprintStore {
    struct Stored: Codable, Equatable {
        let voicePrint: VoicePrint
        let threshold: Float
        let created: Date
    }

    private(set) var stored: Stored?
    private let fileURL: URL?

    init(fileURL: URL? = VoiceprintStore.defaultFileURL()) {
        self.fileURL = fileURL
        stored = fileURL.flatMap { try? JSONDecoder().decode(Stored.self, from: Data(contentsOf: $0)) }
    }

    func save(_ voicePrint: VoicePrint) throws {
        let new = Stored(voicePrint: voicePrint, threshold: voicePrint.suggestedThreshold, created: .now)
        if let fileURL { try PrivateFile.write(try JSONEncoder().encode(new), to: fileURL) }
        stored = new
    }

    func delete() throws {
        if let fileURL, FileManager.default.fileExists(atPath: fileURL.path) { try FileManager.default.removeItem(at: fileURL) }
        stored = nil
    }

    private static func defaultFileURL() -> URL? {
        try? ModelStorage.root().appending(path: "voiceprint.json")
    }
}
