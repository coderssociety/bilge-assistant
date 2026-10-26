import AppKit

/// Short system sounds that mark turn-taking without speech.
enum Earcon {
    case wake
    case cancelled
    case failed

    /// `AudioDevices.Device.uid` of the chosen speaker; nil plays on the system default.
    @MainActor static var outputDeviceUID: String?

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
        // An unplugged speaker would leave the sound unheard; the system default plays it instead.
        sound.playbackDeviceIdentifier = AudioDevices.connected(Self.outputDeviceUID, .output).map { NSSound.PlaybackDeviceIdentifier($0) }
        sound.play()
    }
}
