import AsistanCore
import CoreAudio
import Foundation

/// Which processes are playing sound right now, from Core Audio's process objects. Reading them needs no permission;
/// only tapping their audio would.
enum AudioActivity {
    private static let system = AudioObjectID(kAudioObjectSystemObject)

    /// The bundle identifiers of the processes sending audio to an output; "" for one without an identifier. Empty
    /// when Core Audio cannot tell, which callers must read as "nothing is sounding".
    static func soundingProcesses() -> [String] {
        var address = address(kAudioHardwarePropertyProcessObjectList)
        var size: UInt32 = 0
        guard check(AudioObjectGetPropertyDataSize(system, &address, 0, nil, &size), "process list size") else { return [] }
        var objects = [AudioObjectID](repeating: 0, count: Int(size) / MemoryLayout<AudioObjectID>.size)
        guard check(AudioObjectGetPropertyData(system, &address, 0, nil, &size, &objects), "process list") else { return [] }
        return objects.filter(isRunningOutput).map { bundleIdentifier(of: $0) ?? "" }
    }

    /// Whether an app other than Bilge, Music and Spotify is making sound.
    static func othersSounding() -> Bool {
        let excluded = [Bundle.main.bundleIdentifier ?? ""] + MusicApp.allCases.map(MusicPlayers.bundleIdentifier)
        return BrowserMedia.othersSounding(soundingProcesses(), excluding: excluded.filter { !$0.isEmpty })
    }

    private static func isRunningOutput(_ process: AudioObjectID) -> Bool {
        var address = address(kAudioProcessPropertyIsRunningOutput)
        var running: UInt32 = 0
        var size = UInt32(MemoryLayout<UInt32>.size)
        return AudioObjectGetPropertyData(process, &address, 0, nil, &size, &running) == noErr && running != 0
    }

    private static func bundleIdentifier(of process: AudioObjectID) -> String? {
        var address = address(kAudioProcessPropertyBundleID)
        var identifier: Unmanaged<CFString>?
        var size = UInt32(MemoryLayout<Unmanaged<CFString>?>.size)
        guard AudioObjectGetPropertyData(process, &address, 0, nil, &size, &identifier) == noErr else { return nil }
        return identifier?.takeRetainedValue() as String?
    }

    private static func address(_ selector: AudioObjectPropertySelector) -> AudioObjectPropertyAddress {
        AudioObjectPropertyAddress(mSelector: selector, mScope: kAudioObjectPropertyScopeGlobal,
                                   mElement: kAudioObjectPropertyElementMain)
    }

    private static func check(_ status: OSStatus, _ what: String) -> Bool {
        guard status != noErr else { return true }
        Log.tools.error("Could not read the audio \(what, privacy: .public): \(status, privacy: .public)")
        return false
    }
}
