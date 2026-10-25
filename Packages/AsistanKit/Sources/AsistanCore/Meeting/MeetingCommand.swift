/// "Toplantıyı kaydetmeye başla", "kaydı bitir", "bu ses dosyasını yazıya dök", "son indirdiğim ses kaydını yazıya dök";
/// "record the meeting", "stop recording", "transcribe this audio file".
public enum MeetingCommand: Equatable, Sendable {
    case startRecording
    case stopRecording
    case transcribeFile(AudioFileReference)

    public enum AudioFileReference: Equatable, Sendable {
        /// Selected in Finder or open in the front window.
        case pointed
        /// The newest audio or video file in Downloads.
        case latestDownload
    }

    public static let audioExtensions: Set<String> = ["m4a", "mp3", "wav", "mp4", "aac", "aif", "aiff", "caf", "mov", "m4v"]
    private static let maxStopWords = 6
    private static let maxStartWords = 8

    private static let turkishRecordPrefixes = ["kayd", "kayit"]
    private static let turkishStartPrefixes = ["basla", "baslat"]
    private static let turkishStopPrefixes = ["bitir", "durdur", "kapat", "sonlandir", "bitti"]
    /// Recording something else: the screen, a calendar entry, a note.
    private static let turkishOtherRecordings = ["ekran", "takvim", "not", "hatirlatici", "video", "kamera", "dosya", "belge"]
    private static let turkishTranscribePhrases = ["yaziya dok", "yaziya gecir", "yaziya cevir", "metne dok", "metne cevir",
                                                   "metne gecir", "desifre", "transkript"]
    private static let turkishAudioPrefixes = ["ses", "kayd", "kayit", "dosya", "video", "m4a", "mp3", "wav", "mp4", "toplanti"]

    private static let englishStops: Set<String> = ["stop", "end", "finish", "off", "done", "over", "pause"]
    private static let englishStarts: Set<String> = ["start", "begin", "starting"]
    private static let englishOtherRecordings: Set<String> = ["screen", "video", "camera", "calendar", "note", "reminder"]
    private static let englishAudioPrefixes = ["audio", "recording", "file", "voice", "memo", "video", "download", "m4a", "mp3",
                                               "wav", "mp4", "meeting", "podcast"]
    private static let englishRecentWords: Set<String> = ["last", "latest", "recent", "newest", "downloaded", "downloads", "download"]

    public static func parse(_ text: String, language: AssistantLanguage = .turkish) -> MeetingCommand? {
        let words = TurkishText.folded(text).split(separator: " ").map(String.init)
        guard !words.isEmpty else { return nil }
        return language == .english ? parseEnglish(words) : parseTurkish(words)
    }

    /// What the menu's "end recording" says on the user's behalf.
    public static func stopPhrase(language: AssistantLanguage) -> String {
        language == .english ? "stop recording" : "kaydı bitir"
    }

    private static func parseTurkish(_ words: [String]) -> MeetingCommand? {
        let text = words.joined(separator: " ")
        if turkishTranscribePhrases.contains(where: text.contains),
           words.contains(where: { word in turkishAudioPrefixes.contains(where: word.hasPrefix) }) {
            let recent = words.contains { $0 == "son" || $0.hasPrefix("indir") }
            return .transcribeFile(recent ? .latestDownload : .pointed)
        }
        let recording = words.contains { word in turkishRecordPrefixes.contains(where: word.hasPrefix) }
        let meeting = words.contains { $0.hasPrefix("toplanti") }
        let stops = words.contains { word in turkishStopPrefixes.contains(where: word.hasPrefix) }
        if (recording || meeting), stops, words.count <= maxStopWords { return .stopRecording }
        let other = words.contains { word in turkishOtherRecordings.contains(where: word.hasPrefix) }
        let starts = words.contains { word in turkishStartPrefixes.contains(where: word.hasPrefix) }
        guard recording, !stops, !other, words.count <= maxStartWords, meeting || starts else { return nil }
        return .startRecording
    }

    private static func parseEnglish(_ words: [String]) -> MeetingCommand? {
        if words.contains(where: { $0.hasPrefix("transcrib") }),
           words.contains(where: { word in englishAudioPrefixes.contains(where: word.hasPrefix) }) {
            return .transcribeFile(words.contains(where: englishRecentWords.contains) ? .latestDownload : .pointed)
        }
        let recording = words.contains { $0.hasPrefix("record") }
        let meeting = words.contains { $0.hasPrefix("meeting") }
        let stops = words.contains(where: englishStops.contains)
        if (recording || meeting), stops, words.count <= maxStopWords { return .stopRecording }
        let other = words.contains(where: englishOtherRecordings.contains)
        let starts = words.contains(where: englishStarts.contains)
        guard recording, !stops, !other, words.count <= maxStartWords, meeting || starts else { return nil }
        return .startRecording
    }
}
