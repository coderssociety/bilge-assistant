import Foundation

/// Whether a recording holds anything loud enough to be speech, judged against its own background.
///
/// Speech detection lets through some breaths, rustles and steady machine noise, and Whisper writes a sentence for
/// them anyway. Speech rises well above the noise between words, so a recording is kept only if part of it, long
/// enough for a syllable, stands out from the quietest part of the same recording. Measuring against the recording's
/// own floor makes a fan's steady hum, however loud, count as background.
public enum Loudness {
    public static let frameSeconds = 0.02
    /// How far above the recording's own floor speech rises, and for how long at least.
    static let riseDecibels: Float = 10
    static let minimumLoudSeconds = 0.15
    /// Below this even the loudest part is near the microphone's own noise (dBFS).
    static let silentPeakDecibels: Float = -55
    /// The floor is the level of the quietest tenth of the frames; the peak, of the loudest twentieth.
    private static let floorPercentile = 0.1
    private static let peakPercentile = 0.95
    private static let decibelsOfZero: Float = -120

    /// The level of each 20 ms frame in dBFS.
    public static func frameLevels(_ samples: [Float], sampleRate: Double) -> [Float] {
        let size = max(1, Int(sampleRate * frameSeconds))
        guard samples.count >= size else { return [] }
        return stride(from: 0, through: samples.count - size, by: size).map { start in
            var power: Float = 0
            for index in start..<(start + size) { power += samples[index] * samples[index] }
            power /= Float(size)
            return power > 0 ? 10 * log10(power) : decibelsOfZero
        }
    }

    public static func holdsSpeech(_ samples: [Float], sampleRate: Double) -> Bool {
        holdsSpeech(levels: frameLevels(samples, sampleRate: sampleRate))
    }

    static func holdsSpeech(levels: [Float]) -> Bool {
        guard !levels.isEmpty else { return false }
        let ordered = levels.sorted()
        func percentile(_ fraction: Double) -> Float {
            ordered[min(ordered.count - 1, Int(fraction * Double(ordered.count)))]
        }
        guard percentile(peakPercentile) >= silentPeakDecibels else { return false }
        let floor = percentile(floorPercentile)
        let loud = levels.count(where: { $0 >= floor + riseDecibels })
        return Double(loud) * frameSeconds >= minimumLoudSeconds
    }
}
