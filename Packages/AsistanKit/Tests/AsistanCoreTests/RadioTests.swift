import Foundation
import Testing
@testable import AsistanCore

@Suite("Radio")
struct RadioTests {
    /// Trimmed from radio-browser's search for "power" in Türkiye, plus a broken and an unplayable station.
    private let search = Data("""
    [{"name":"Power POP","url":"https://listen.powerapp.com.tr/powerpop/128/chunks.m3u8","url_resolved":"https://listen.powerapp.com.tr/powerpop/128/chunks.m3u8","codec":"UNKNOWN","votes":11396,"hls":1,"lastcheckok":1},
     {"name":"POWER TÜRK FM","url_resolved":"https://live.powerapp.com.tr/powerturk/abr/powerturk/128/playlist.m3u8","codec":"AAC","votes":1496,"hls":1,"lastcheckok":1},
     {"name":"Power FM Türkiye","url_resolved":"https://listen.powerapp.com.tr/powerfm/256/chunks.m3u8","codec":"UNKNOWN","votes":950,"hls":1,"lastcheckok":1},
     {"name":"Power FM","url_resolved":"http://example.org/powerfm.ogg","codec":"OGG","votes":5000,"hls":0,"lastcheckok":1},
     {"name":"Power FM Türkiye","url_resolved":"https://example.org/broken","codec":"MP3","votes":9000,"hls":0,"lastcheckok":0},
     {"name":"Power FM Türkiye","url_resolved":"","url":"ftp://example.org/x","codec":"MP3","votes":20,"hls":0,"lastcheckok":1},
     {"votes":"çok"}]
    """.utf8)

    private let virgin = Data("""
    [{"name":"Virgin Radio Türkiye","url_resolved":"http://28933.live.streamtheworld.com/VIRGIN_RADIO_SC","codec":"MP3","votes":20659,"hls":0,"lastcheckok":1},
     {"name":"Virgin Radio Türkiye","url_resolved":"http://29333.live.streamtheworld.com/VIRGIN_RADIOAAC_SC","codec":"AAC+","votes":663,"hls":0,"lastcheckok":1},
     {"name":"Virgin Radio Türkiye","url_resolved":"https://example.org/virgin","codec":"MP3","votes":35,"hls":0,"lastcheckok":1}]
    """.utf8)

    @Test("stations are decoded defensively")
    func decoding() {
        let stations = RadioStation.list(from: search)
        #expect(stations.count == 7)
        #expect(stations[0].isHLS && stations[0].votes == 11396)
        #expect(stations[5].streamURL?.scheme == "ftp")
        #expect(stations[6].name.isEmpty && stations[6].streamURL == nil)
        #expect(RadioStation.list(from: Data("bozuk".utf8)).isEmpty)
    }

    @Test("the station named like the request wins over more voted ones")
    func choice() {
        let ranked = RadioStationChoice.ranked(RadioStation.list(from: search), for: "Power FM")
        #expect(ranked.map(\.name) == ["Power FM Türkiye", "POWER TÜRK FM"])
        #expect(ranked.first?.streamURL?.absoluteString == "https://listen.powerapp.com.tr/powerfm/256/chunks.m3u8")
        #expect(RadioStationChoice.ranked(RadioStation.list(from: search), for: "Kral FM").isEmpty)
    }

    @Test("among equally named stations https comes first, then votes")
    func secureFirst() {
        let ranked = RadioStationChoice.ranked(RadioStation.list(from: virgin), for: "Virgin Radio")
        #expect(ranked.map(\.votes) == [35, 20659, 663])
    }

    @Test("popular stations are found by what people call them", arguments: [
        ("trt fm", "TRT FM"), ("Süper FM", "Süper FM"), ("super fm", "Süper FM"), ("joy türk", "Joy Türk"), ("Radyo 7", "Radyo 7"),
        ("radyo yedi", "Radyo 7"), ("virgin", "Virgin Radio"),
    ])
    func popular(phrase: String, name: String) {
        #expect(PopularRadioStations.entry(named: phrase)?.name == name)
    }

    @Test("Turkish radio commands", arguments: [
        ("radyo aç", RadioCommand.play(station: nil)), ("radyoyu aç", .play(station: nil)),
        ("Power FM aç", .play(station: "Power FM")), ("TRT FM çal", .play(station: "TRT FM")),
        ("Virgin Radio'yu aç", .play(station: "Virgin Radio")), ("Virgin Radioyu açar mısın", .play(station: "Virgin Radio")),
        ("Joy Türk aç", .play(station: "Joy Türk")), ("bana biraz radyo açsana", .play(station: nil)),
        ("Radyo Viva'yı aç", .play(station: "Radyo Viva")), ("radyo dinlemek istiyorum", .play(station: nil)),
        ("radyoyu kapat", .stop), ("radyoyu durdur", .stop), ("Power FM'i kapat", .stop),
        ("radyonun sesini kıs", .volume(louder: false)), ("radyonun sesini aç", .volume(louder: true)),
        ("radyoyu biraz kıs", .volume(louder: false)),
        ("hangi radyo çalıyor", .nowPlaying), ("bu hangi radyo", .nowPlaying), ("radyoda ne çalıyor", .nowPlaying),
    ])
    func turkish(command: String, expected: RadioCommand) {
        #expect(RadioRequest.parse(command) == expected)
    }

    @Test("other requests are left to the music and other tools", arguments: [
        "Tarkan çal", "Galatasaray marşını çal", "müziği aç", "Spotify'ı aç", "sesini kıs", "durdur", "devam et",
        "TRT FM'in sitesini aç", "sesi kıs", "radyo nedir", "Kral FM'in frekansı ne", "müziği durdur", "PowerPoint aç",
    ])
    func notRadio(command: String) {
        #expect(RadioRequest.parse(command) == nil)
    }

    @Test("with something playing, bare commands are about it")
    func playing() {
        #expect(RadioRequest.parse("durdur", stream: .playing) == .stop)
        #expect(RadioRequest.parse("sesini biraz kıs", stream: .playing) == .volume(louder: false))
        #expect(RadioRequest.parse("sesini artır", stream: .playing) == .volume(louder: true))
        #expect(RadioRequest.parse("devam et", stream: .playing) == nil)
        #expect(RadioRequest.parse("devam et", stream: .paused) == .resume)
        #expect(RadioRequest.parse("müziği durdur", stream: .playing) == nil)
        #expect(RadioRequest.parse("sesi kıs", stream: .playing) == nil)
    }

    @Test("a paused stream only takes a bare resume, so stop and volume reach the music")
    func paused() {
        #expect(RadioRequest.parse("devam et", stream: .paused) == .resume)
        #expect(RadioRequest.parse("durdur", stream: .paused) == nil)
        #expect(RadioRequest.parse("sesini kıs", stream: .paused) == nil)
        #expect(RadioRequest.parse("müziği durdur", stream: .paused) == nil)
        #expect(RadioRequest.parse("resume", language: .english, stream: .paused) == .resume)
        #expect(RadioRequest.parse("stop", language: .english, stream: .paused) == nil)
        #expect(RadioRequest.parse("turn it down", language: .english, stream: .paused) == nil)
        #expect(RadioRequest.parse("stop", language: .english, stream: .playing) == .stop)
    }

    @Test("a command for later is not carried out now", arguments: [
        "30 dakika sonra radyoyu kapat", "radyoyu yarım saat sonra kapat", "radyoyu 1 saat sonra kapat",
        "10 dakikaya kadar radyoyu kapat", "turn off the radio in 30 minutes", "stop the radio after an hour",
    ])
    func delayed(command: String) {
        let language: AssistantLanguage = command.hasPrefix("turn") || command.hasPrefix("stop") ? .english : .turkish
        #expect(RadioRequest.parse(command, language: language) == nil)
        #expect(RadioRequest.parse(command, language: language, stream: .playing) == nil)
    }

    @Test("English radio commands", arguments: [
        ("play the radio", RadioCommand.play(station: nil)), ("turn on the radio", .play(station: nil)),
        ("play Power FM", .play(station: "Power FM")), ("put on Virgin Radio", .play(station: "Virgin Radio")),
        ("turn off the radio", .stop), ("stop the radio", .stop), ("turn the radio down", .volume(louder: false)),
        ("turn up the radio", .volume(louder: true)), ("which radio station is playing", .nowPlaying),
        ("what's on the radio", .nowPlaying),
    ])
    func english(command: String, expected: RadioCommand) {
        #expect(RadioRequest.parse(command, language: .english) == expected)
    }

    @Test("English requests for other tools", arguments: ["play Tarkan", "open Safari", "stop", "turn it down", "play some Queen"])
    func englishNotRadio(command: String) {
        #expect(RadioRequest.parse(command, language: .english) == nil)
    }
}
