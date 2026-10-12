import AppKit

/// Short system sounds that mark turn-taking without speech.
enum Earcon {
    case wake
    case cancelled
    case failed

    private var soundName: NSSound.Name {
        switch self {
        case .wake: "Tink"
        case .cancelled: "Pop"
        case .failed: "Basso"
        }
    }

    @MainActor
    func play() {
        guard let sound = NSSound(named: soundName) else {
            Log.audio.error("System sound \(soundName, privacy: .public) is missing")
            return
        }
        sound.play()
    }
}
