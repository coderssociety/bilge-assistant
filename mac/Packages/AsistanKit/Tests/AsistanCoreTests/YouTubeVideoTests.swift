import Foundation
import Testing
@testable import AsistanCore

@Suite("YouTube videos")
struct YouTubeVideoTests {
    /// Trimmed from youtubei/v1/player (ANDROID client), plus a track on another host that must be dropped.
    private let player = Data("""
    {"playabilityStatus":{"status":"OK"},"videoDetails":{"videoId":"dQw4w9WgXcQ","title":"Rick Astley - Never Gonna Give You Up"},
     "captions":{"playerCaptionsTracklistRenderer":{"captionTracks":[
      {"baseUrl":"https://www.youtube.com/api/timedtext?v=dQw4w9WgXcQ&caps=asr&sparams=ip%2Cexpire&lang=de-DE&fmt=srv3","languageCode":"de-DE"},
      {"baseUrl":"https://www.youtube.com/api/timedtext?v=dQw4w9WgXcQ&lang=en&fmt=srv3","languageCode":"en"},
      {"baseUrl":"https://www.youtube.com/api/timedtext?v=dQw4w9WgXcQ&kind=asr&lang=en","languageCode":"en","kind":"asr"},
      {"baseUrl":"https://evil.example/api/timedtext?lang=tr","languageCode":"tr"},
      {"languageCode":"ja"}]}}}
    """.utf8)

    @Test("the video id is read from watch, short, shorts, embed and live links", arguments: [
        ("https://www.youtube.com/watch?v=dQw4w9WgXcQ", "dQw4w9WgXcQ"),
        ("şu videoyu özetle youtube.com/watch?feature=share&v=dQw4w9WgXcQ&t=42s", "dQw4w9WgXcQ"),
        ("https://youtu.be/dQw4w9WgXcQ?si=abc", "dQw4w9WgXcQ"),
        ("https://m.youtube.com/shorts/aBcD_-12345", "aBcD_-12345"),
        ("https://www.youtube-nocookie.com/embed/dQw4w9WgXcQ", "dQw4w9WgXcQ"),
        ("https://www.youtube.com/live/dQw4w9WgXcQ", "dQw4w9WgXcQ"),
    ])
    func id(text: String, expected: String) {
        #expect(YouTubeVideo.id(in: text) == expected)
    }

    @Test("other addresses have no video id", arguments: [
        "https://www.youtube.com/", "https://notyoutube.com/watch?v=dQw4w9WgXcQ", "https://vimeo.com/123456789",
        "https://youtu.be/kisa", "https://www.youtube.com/watch?v=dQw4w9WgXcQextra", "bu videoyu özetle",
    ])
    func noID(text: String) {
        #expect(YouTubeVideo.id(in: text) == nil)
    }

    @Test("the player answer gives the title and the caption tracks on youtube.com, in the plain format")
    func details() throws {
        let video = YouTubeVideo.details(fromPlayer: player)
        #expect(video.title == "Rick Astley - Never Gonna Give You Up")
        #expect(video.isPlayable)
        #expect(video.tracks.map(\.language) == ["de-DE", "en", "en"])
        #expect(video.tracks.map(\.isAutomatic) == [false, false, true])
        let german = try #require(video.tracks.first?.url.absoluteString)
        #expect(!german.contains("fmt="))
        #expect(german.contains("sparams=ip%2Cexpire"))
    }

    @Test("a broken or unplayable answer has nothing to read")
    func unknown() {
        #expect(YouTubeVideo.details(fromPlayer: Data("bozuk".utf8)) == .unknown)
        let removed = YouTubeVideo.details(fromPlayer: Data(#"{"playabilityStatus":{"status":"ERROR"}}"#.utf8))
        #expect(!removed.isPlayable)
        #expect(removed.tracks.isEmpty)
    }

    private func track(_ language: String, automatic: Bool = false) -> YouTubeVideo.Track {
        YouTubeVideo.Track(language: language, isAutomatic: automatic, url: URL(string: "https://www.youtube.com/api/timedtext?lang=\(language)")!)
    }

    @Test("Turkish captions first, written before generated")
    func turkishFirst() {
        let tracks = [track("en"), track("tr", automatic: true), track("tr-TR")]
        #expect(YouTubeVideo.track(in: tracks, preferring: "tr") == track("tr-TR"))
        #expect(YouTubeVideo.track(in: [track("en"), track("tr", automatic: true)], preferring: "tr") == track("tr", automatic: true))
    }

    @Test("without Turkish, the language the video speaks, then English, then anything written")
    func fallbacks() {
        #expect(YouTubeVideo.track(in: [track("en"), track("de", automatic: true), track("de")], preferring: "tr") == track("de"))
        #expect(YouTubeVideo.track(in: [track("de", automatic: true), track("en")], preferring: "tr") == track("de", automatic: true))
        #expect(YouTubeVideo.track(in: [track("fr"), track("en")], preferring: "tr") == track("en"))
        #expect(YouTubeVideo.track(in: [track("fr"), track("ja")], preferring: "tr") == track("fr"))
        #expect(YouTubeVideo.track(in: [], preferring: "tr") == nil)
    }

    @Test("the simple caption format, escaped twice, becomes one text")
    func simpleTranscript() {
        let xml = Data("""
        <?xml version="1.0" encoding="utf-8" ?><transcript><text start="1.36" dur="1.68">[Müzik]</text>\
        <text start="18.64" dur="3.24">We&amp;#39;re no strangers
        to love</text><text start="22" dur="1"> </text><text start="23" dur="2">Tom &amp;amp; Jerry</text></transcript>
        """.utf8)
        #expect(YouTubeVideo.transcript(from: xml) == "[Müzik] We're no strangers to love Tom & Jerry")
    }

    @Test("the timed caption format and a file cut short")
    func timedTranscript() {
        let timed = Data("""
        <timedtext format="3"><body><p t="0" d="1000"><s>Merhaba</s><s> arkadaşlar</s></p><p t="1000">bugün</p></body></timedtext>
        """.utf8)
        #expect(YouTubeVideo.transcript(from: timed) == "Merhaba arkadaşlar bugün")
        #expect(YouTubeVideo.transcript(from: Data("<transcript><text>Bir</text><text>İk".utf8)) == "Bir")
        #expect(YouTubeVideo.transcript(from: Data()) == "")
    }

    @Test("video summary requests", arguments: [
        ("bu videoyu özetle", VideoSummaryCommand()),
        ("şu videoyu özetler misin", VideoSummaryCommand()),
        ("bu video ne anlatıyor", VideoSummaryCommand()),
        ("videoda neden bahsediliyor", VideoSummaryCommand()),
        ("YouTube videosunu kısaca özetle", VideoSummaryCommand()),
        ("panodaki videoyu özetle", VideoSummaryCommand(fromClipboard: true)),
        ("kopyaladığım videoyu özetle", VideoSummaryCommand(fromClipboard: true)),
        ("şunu özetle https://youtu.be/dQw4w9WgXcQ", VideoSummaryCommand(videoID: "dQw4w9WgXcQ")),
    ])
    func turkish(command: String, expected: VideoSummaryCommand) {
        #expect(VideoSummaryRequest.parse(command) == expected)
    }

    @Test("other requests are left alone", arguments: [
        "bu sayfayı özetle", "videoyu durdur", "videoyu aç", "devamını özetle", "bu maili özetle",
        "YouTube'da Tarkan aç", "son bölümü özetle", "video nasıl çekilir",
    ])
    func notVideoSummary(command: String) {
        #expect(VideoSummaryRequest.parse(command) == nil)
    }

    @Test("English video summary requests", arguments: [
        ("summarize this video", VideoSummaryCommand()), ("sum up the YouTube video", VideoSummaryCommand()),
        ("what's this video about", VideoSummaryCommand()),
        ("summarize the video on the clipboard", VideoSummaryCommand(fromClipboard: true)),
        ("summarize https://www.youtube.com/watch?v=dQw4w9WgXcQ", VideoSummaryCommand(videoID: "dQw4w9WgXcQ")),
    ])
    func english(command: String, expected: VideoSummaryCommand) {
        #expect(VideoSummaryRequest.parse(command, language: .english) == expected)
    }

    @Test("English requests for other tools", arguments: ["summarize this page", "pause the video", "summarize the rest", "play a video"])
    func englishNotVideoSummary(command: String) {
        #expect(VideoSummaryRequest.parse(command, language: .english) == nil)
    }

    @Test("video summaries are not taken for podcasts or radio")
    func otherMedia() {
        #expect(PodcastRequest.parse("bu videoyu özetle") == nil)
        #expect(RadioRequest.parse("bu videoyu özetle") == nil)
        #expect(VideoSummaryRequest.parse("Mesele Ekonomi podcastinin son bölümünü aç") == nil)
    }
}
