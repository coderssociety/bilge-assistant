import AppKit
import AsistanCore
import FoundationModels

/// "Bu videoyu özetle" for the YouTube video open in the browser, "şu videoyu özetle" with an address in the command
/// or on the clipboard. The captions come from YouTube's player service as its phone apps ask for them (no key; the
/// watch page's own caption links now need a token only a browser makes). They are untrusted text, answered by the
/// tool-less session; "devamını özetle" goes on with the next part. Routed by rule, ahead of the page tools.
struct YouTubeSummaryTool: RuleRoutedTool {
    let name = "summarizeVideo"
    let description = "Tarayıcıda açık ya da adresi verilen YouTube videosunu altyazısından özetler."
    let answersWithLanguageModel = true
    let readingLayout: ContinuedReading.Layout? = .text(maxCharacters: BrowserPage.maxCharacters)
    private static let playerURL = URL(string: "https://www.youtube.com/youtubei/v1/player?prettyPrint=false")!
    /// Tried in turn; YouTube changes which clients get captions without a token every few months.
    private static let clients = [
        ["clientName": "ANDROID", "clientVersion": "20.10.38"],
        ["clientName": "IOS", "clientVersion": "20.10.4"],
    ]

    @Generable
    struct Arguments {
        @Guide(description: "Kullanıcının isteği, olduğu gibi")
        var request: String
    }

    @MainActor
    func claims(_ command: String) -> Bool {
        VideoSummaryRequest.parse(command, language: AppLanguage.current) != nil
    }

    func arguments(fromCommand command: String) -> Arguments? {
        Arguments(request: command)
    }

    func call(arguments: Arguments) async throws -> String {
        let language = AppLanguage.current
        guard let command = VideoSummaryRequest.parse(arguments.request, language: language) else {
            return ToolReply.failure(String(localized: "Hangi videoyu özetleyeceğimi anlayamadım."))
        }
        let id: String
        do {
            guard let found = try await Self.videoID(for: command) else {
                return ToolReply.failure(String(localized: "Özetleyecek bir YouTube videosu bulamadım. Videoyu tarayıcıda aç ya da adresini kopyalayıp yine söyler misin?"))
            }
            id = found
        } catch {
            return ToolReply.failure(String(localized: "Tarayıcıdaki videoya ulaşamadım. \(error.localizedDescription)"))
        }
        let video: YouTubeVideo.Details
        do {
            video = try await Self.details(of: id, language: language)
        } catch {
            return ToolReply.failure(String(localized: "Videonun bilgilerini alamadım. \(error.localizedDescription)"))
        }
        guard video.isPlayable else {
            return ToolReply.failure(String(localized: "Bu videoyu açamadım; özel, kaldırılmış ya da yaş sınırlı olabilir."))
        }
        guard let track = YouTubeVideo.track(in: video.tracks, preferring: language.code) else {
            return ToolReply.failure(String(localized: "Bu videonun altyazısı yok, o yüzden özetleyemiyorum."))
        }
        let transcript: String
        do {
            transcript = YouTubeVideo.transcript(from: try await WebFetch.data(from: track.url))
        } catch {
            return ToolReply.failure(String(localized: "Videonun altyazısını alamadım. \(error.localizedDescription)"))
        }
        guard !transcript.isEmpty else {
            return ToolReply.failure(String(localized: "Bu videonun altyazısı yok, o yüzden özetleyemiyorum."))
        }
        let title = video.title.isEmpty ? id : video.title
        let heading = track.isAutomatic
            ? String(localized: "Video: \(title) (otomatik \(track.language) altyazısından)")
            : String(localized: "Video: \(title) (\(track.language) altyazısından)")
        return heading + "\n\n" + transcript
    }

    /// The address in the command; else, unless the clipboard was named, the video open in the browser; else the one
    /// on the clipboard. A browser that could not be asked is reported only when the clipboard has no video either.
    private static func videoID(for command: VideoSummaryCommand) async throws -> String? {
        if let id = command.videoID { return id }
        let copied = await MainActor.run { NSPasteboard.general.string(forType: .string) }.flatMap(YouTubeVideo.id(in:))
        if command.fromClipboard { return copied }
        do {
            if let page = try await BrowserPage.current(frontmostOnly: false), let id = YouTubeVideo.id(in: page.url.absoluteString) {
                return id
            }
        } catch {
            guard let copied else { throw error }
            Log.tools.info("Browser page unavailable, using the clipboard: \(error.localizedDescription, privacy: .public)")
        }
        return copied
    }

    /// The first client whose answer is playable with captions; the last answer otherwise.
    private static func details(of id: String, language: AssistantLanguage) async throws -> YouTubeVideo.Details {
        var found = YouTubeVideo.Details.unknown
        var lastError: (any Error)?
        for client in clients {
            let body: [String: Any] = ["context": ["client": client.merging(["hl": language.code]) { $1 }], "videoId": id]
            do {
                let answer = try await WebFetch.post(json: try JSONSerialization.data(withJSONObject: body), to: playerURL)
                found = YouTubeVideo.details(fromPlayer: answer)
            } catch is CancellationError {
                throw CancellationError()
            } catch {
                Log.tools.error("YouTube player (\(client["clientName"] ?? "", privacy: .public)) failed: \(error.localizedDescription, privacy: .public)")
                lastError = error
                continue
            }
            if found.isPlayable, !found.tracks.isEmpty { return found }
        }
        if !found.isPlayable, let lastError { throw lastError }
        return found
    }
}
