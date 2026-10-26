import Foundation

public struct VideoSummaryCommand: Sendable, Equatable {
    /// The video of a YouTube address said or typed in the command.
    public let videoID: String?
    /// "Panodaki videoyu özetle": the address is on the clipboard rather than open in the browser.
    public let fromClipboard: Bool

    public init(videoID: String? = nil, fromClipboard: Bool = false) {
        self.videoID = videoID
        self.fromClipboard = fromClipboard
    }
}

/// "Bu videoyu özetle", "şu videoyu özetle https://youtu.be/…", "panodaki videoyu özetle", "bu video ne anlatıyor";
/// "summarize this video", "what's this YouTube video about". A page, a document or an episode is left to other tools.
public enum VideoSummaryRequest {
    private static let videoStems = ["video", "youtube"]
    private static let clipboardStems = ["pano", "kopyala"]
    private static let questionWords: Set<String> = ["ne", "neyi", "neden", "neler", "nelerden"]
    private static let aboutStems = ["anlat", "bahs"]
    private static let englishVideoWords: Set<String> = ["video", "videos", "youtube", "clip"]
    private static let englishSummaryWords: Set<String> = ["summarize", "summarise", "summary", "recap", "tldr", "gist"]

    public static func parse(_ text: String, language: AssistantLanguage = .turkish) -> VideoSummaryCommand? {
        let words = TurkishText.folded(text).split(separator: " ").map(String.init)
        let id = YouTubeVideo.id(in: text)
        guard !words.isEmpty else { return nil }
        return language == .english ? english(words, id: id) : turkish(words, id: id)
    }

    private static func turkish(_ words: [String], id: String?) -> VideoSummaryCommand? {
        let mentionsVideo = id != nil || words.contains { word in videoStems.contains(where: word.hasPrefix) }
        let summarizes = words.contains { $0.hasPrefix("ozet") }
            || (words.contains(where: questionWords.contains) && words.contains { word in aboutStems.contains(where: word.hasPrefix) })
        guard mentionsVideo, summarizes else { return nil }
        let fromClipboard = words.contains { word in clipboardStems.contains(where: word.hasPrefix) }
        return VideoSummaryCommand(videoID: id, fromClipboard: fromClipboard)
    }

    private static func english(_ words: [String], id: String?) -> VideoSummaryCommand? {
        let mentionsVideo = id != nil || words.contains(where: englishVideoWords.contains)
        let summarizes = words.contains(where: englishSummaryWords.contains)
            || zip(words, words.dropFirst()).contains { $0 == "sum" && $1 == "up" }
            || (words.contains { $0 == "what" || $0 == "whats" } && words.contains("about"))
        guard mentionsVideo, summarizes else { return nil }
        return VideoSummaryCommand(videoID: id, fromClipboard: words.contains { $0 == "clipboard" || $0 == "copied" })
    }
}
