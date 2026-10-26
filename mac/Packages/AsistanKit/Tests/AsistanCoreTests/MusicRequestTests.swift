import Testing
@testable import AsistanCore

@Suite("Music on a named service")
struct MusicRequestTests {
    @Test("a song asked for on a named service", arguments: [
        ("YouTube'da Tarkan aç", "Tarkan", MusicService.youTube),
        ("youtubeda tarkan aç", "tarkan", .youTube),
        ("You Tube'da Kuzu Kuzu'yu çal", "Kuzu Kuzu", .youTube),
        ("YouTube Music'te Sezen Aksu çal", "Sezen Aksu", .youTubeMusic),
        ("YouTube Müzik'ten Sezen Aksu çalar mısın", "Sezen Aksu", .youTubeMusic),
        ("Deezer'da Kuzu Kuzu çal", "Kuzu Kuzu", .deezer),
        ("Spotify'da Tarkan'ın şarkılarını çal", "Tarkan", .spotify),
        ("Kuzu Kuzu'yu Spotify'dan çal", "Kuzu Kuzu", .spotify),
        ("Bilge, Apple Music'te Tarkan çal lütfen", "Tarkan", .appleMusic),
        ("Spotify üzerinden Şımarık çal", "Şımarık", .spotify),
        ("YouTube'da bir Barış Manço şarkısı aç", "Barış Manço", .youTube),
        ("play Tarkan on YouTube", "Tarkan", .youTube),
        ("play Kuzu Kuzu on YouTube Music", "Kuzu Kuzu", .youTubeMusic),
        ("can you play some Sezen Aksu on Deezer", "Sezen Aksu", .deezer),
        ("put on Kuzu Kuzu in Apple Music", "Kuzu Kuzu", .appleMusic),
        ("listen to Tarkan on Spotify", "Tarkan", .spotify),
    ])
    func named(command: String, query: String, service: MusicService) {
        #expect(MusicRequest.parse(command) == MusicRequest(query: query, service: service))
    }

    @Test("the service itself, nothing named to play, or no service is not one", arguments: [
        "YouTube'u aç", "YouTube'u açar mısın", "Spotify'ı aç", "open YouTube", "open Spotify",
        "Spotify'da müzik çal", "YouTube'da bir video aç", "play something on Deezer",
        "Tarkan çal", "play Tarkan", "YouTube'da ne var",
    ])
    func notOne(command: String) {
        #expect(MusicRequest.parse(command) == nil)
    }

    @Test("the browser and video-summary rules leave these commands alone", arguments: [
        "YouTube'da Tarkan aç", "YouTube Music'te Sezen Aksu çal", "play Tarkan on YouTube",
    ])
    func otherRulesPass(command: String) {
        #expect(BrowserCommand.parse(command, language: .turkish) == nil)
        #expect(BrowserCommand.parse(command, language: .english) == nil)
        #expect(VideoSummaryRequest.parse(command, language: .turkish) == nil)
        #expect(VideoSummaryRequest.parse(command, language: .english) == nil)
    }
}

@Suite("Music service choice")
struct MusicServiceTests {
    @Test("the service said wins, then the one set; the playing app is asked only with neither")
    func choice() async throws {
        let never: () async throws -> MusicApp = { Issue.record("asked"); return .music }
        #expect(try await MusicService.forRequest(named: .deezer, preferred: .youTube, automatic: never) == .deezer)
        #expect(try await MusicService.forRequest(named: nil, preferred: .appleMusic, automatic: never) == .appleMusic)
        #expect(try await MusicService.forRequest(named: nil, preferred: nil, automatic: { .spotify }) == .spotify)
        #expect(try await MusicService.forRequest(named: nil, preferred: nil, automatic: { .music }) == .appleMusic)
    }
}
