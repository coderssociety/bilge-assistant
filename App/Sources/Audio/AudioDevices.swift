@preconcurrency import AVFoundation
import CoreAudio

/// Microphones and speakers the user can pick instead of the system's defaults. A choice is kept by the device's UID,
/// which survives unplugging and restarts; a device that is gone falls back to the system default.
enum AudioDevices {
    struct Device: Identifiable, Hashable {
        let uid: String
        let name: String
        var id: String { uid }
    }

    enum Direction {
        case input
        case output

        var scope: AudioObjectPropertyScope {
            self == .input ? kAudioObjectPropertyScopeInput : kAudioObjectPropertyScopeOutput
        }
    }

    /// Everything Bilge plays goes to one speaker: its voice, radio and podcasts, and the short sounds.
    @MainActor
    static func selectOutput(_ uid: String?, speech: SpeechOutput) {
        speech.useOutputDevice(uid)
        StreamPlayer.shared.useOutputDevice(uid)
        Earcon.outputDeviceUID = uid
    }

    /// `uid` while that device is plugged in; nil, meaning the system default, otherwise.
    static func connected(_ uid: String?, _ direction: Direction) -> String? {
        guard let uid, let device = deviceID(forUID: uid), channelCount(of: device, direction) > 0 else { return nil }
        return uid
    }

    static func list(_ direction: Direction) -> [Device] {
        allDeviceIDs().filter { channelCount(of: $0, direction) > 0 }.compactMap { id in
            guard let uid = string(kAudioDevicePropertyDeviceUID, of: id),
                  let name = string(kAudioObjectPropertyName, of: id) else { return nil }
            return Device(uid: uid, name: name)
        }
        .sorted { $0.name.localizedStandardCompare($1.name) == .orderedAscending }
    }

    /// Points an engine's input or output node at the device with `uid`, or at the system default for nil or a device
    /// that is gone. An engine left alone follows the default by itself, so callers only call this once a device was
    /// chosen.
    static func apply(_ uid: String?, to node: AVAudioIONode, _ direction: Direction) {
        guard let unit = node.audioUnit else { return }
        let chosen = uid.flatMap(deviceID(forUID:)).flatMap { channelCount(of: $0, direction) > 0 ? $0 : nil }
        if uid != nil, chosen == nil { Log.audio.info("Chosen audio device is not connected; using the system default") }
        guard var device = chosen ?? defaultDevice(direction) else { return }
        let status = AudioUnitSetProperty(unit, kAudioOutputUnitProperty_CurrentDevice, kAudioUnitScope_Global, 0,
                                          &device, UInt32(MemoryLayout<AudioDeviceID>.size))
        if status != noErr { Log.audio.error("Could not switch audio device (\(status))") }
    }

    private static func allDeviceIDs() -> [AudioDeviceID] {
        var address = AudioObjectPropertyAddress(mSelector: kAudioHardwarePropertyDevices,
                                                 mScope: kAudioObjectPropertyScopeGlobal,
                                                 mElement: kAudioObjectPropertyElementMain)
        var size: UInt32 = 0
        guard AudioObjectGetPropertyDataSize(AudioObjectID(kAudioObjectSystemObject), &address, 0, nil, &size) == noErr else {
            return []
        }
        var ids = [AudioDeviceID](repeating: 0, count: Int(size) / MemoryLayout<AudioDeviceID>.size)
        guard AudioObjectGetPropertyData(AudioObjectID(kAudioObjectSystemObject), &address, 0, nil, &size, &ids) == noErr else {
            return []
        }
        return ids
    }

    private static func defaultDevice(_ direction: Direction) -> AudioDeviceID? {
        var address = AudioObjectPropertyAddress(
            mSelector: direction == .input ? kAudioHardwarePropertyDefaultInputDevice : kAudioHardwarePropertyDefaultOutputDevice,
            mScope: kAudioObjectPropertyScopeGlobal, mElement: kAudioObjectPropertyElementMain)
        var device = AudioDeviceID(0)
        var size = UInt32(MemoryLayout<AudioDeviceID>.size)
        guard AudioObjectGetPropertyData(AudioObjectID(kAudioObjectSystemObject), &address, 0, nil, &size, &device) == noErr,
              device != 0 else { return nil }
        return device
    }

    private static func deviceID(forUID uid: String) -> AudioDeviceID? {
        allDeviceIDs().first { string(kAudioDevicePropertyDeviceUID, of: $0) == uid }
    }

    private static func channelCount(of device: AudioDeviceID, _ direction: Direction) -> Int {
        var address = AudioObjectPropertyAddress(mSelector: kAudioDevicePropertyStreamConfiguration,
                                                 mScope: direction.scope, mElement: kAudioObjectPropertyElementMain)
        var size: UInt32 = 0
        guard AudioObjectGetPropertyDataSize(device, &address, 0, nil, &size) == noErr, size > 0 else { return 0 }
        let raw = UnsafeMutableRawPointer.allocate(byteCount: Int(size), alignment: MemoryLayout<AudioBufferList>.alignment)
        defer { raw.deallocate() }
        guard AudioObjectGetPropertyData(device, &address, 0, nil, &size, raw) == noErr else { return 0 }
        let buffers = UnsafeMutableAudioBufferListPointer(raw.assumingMemoryBound(to: AudioBufferList.self))
        return buffers.reduce(0) { $0 + Int($1.mNumberChannels) }
    }

    private static func string(_ selector: AudioObjectPropertySelector, of device: AudioDeviceID) -> String? {
        var address = AudioObjectPropertyAddress(mSelector: selector, mScope: kAudioObjectPropertyScopeGlobal,
                                                 mElement: kAudioObjectPropertyElementMain)
        var value: Unmanaged<CFString>?
        var size = UInt32(MemoryLayout<Unmanaged<CFString>?>.size)
        guard AudioObjectGetPropertyData(device, &address, 0, nil, &size, &value) == noErr, let value else { return nil }
        return value.takeRetainedValue() as String
    }
}
