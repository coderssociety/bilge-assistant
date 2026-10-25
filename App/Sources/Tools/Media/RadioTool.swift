import AsistanCore
import Foundation
import FoundationModels

/// "Power FM aç", "radyoyu kapat", "radyonun sesini kıs", "hangi radyo çalıyor". Stations come from radio-browser.info
/// and play inside Bilge (`StreamPlayer`); "radyoyu aç" plays the last one. Routed by rule: the router model would
/// send station names to playMusic.
struct RadioTool: RuleRoutedTool {
    let name = "radio"
    let description = "İnternet radyosu çalar, kapatır, sesini ayarlar ve hangi radyonun çaldığını söyler."
    private static let lastStationKey = "radio.lastStation"
    private static let lastStationURLKey = "radio.lastStationURL"
    private static let candidatesToTry = 3

    @Generable
    struct Arguments {
        @Guide(description: "Kullanıcının isteği, olduğu gibi")
        var request: String
    }

    @MainActor
    func claims(_ command: String) -> Bool {
        RadioRequest.parse(command, language: AppLanguage.current, stream: StreamPlayer.shared.state) != nil
    }

    func arguments(fromCommand command: String) -> Arguments? {
        Arguments(request: command)
    }

    func call(arguments: Arguments) async throws -> String {
        let language = AppLanguage.current
        let state = await StreamPlayer.shared.state
        guard let command = RadioRequest.parse(arguments.request, language: language, stream: state) else {
            return ToolReply.failure(String(localized: "Hangi radyoyu istediğini anlayamadım."))
        }
        switch command {
        case let .play(station): return await play(station)
        case .stop: return await StreamReplies.stop()
        case .resume: return try await resume()
        case .nowPlaying: return await StreamReplies.nowPlaying()
        case let .volume(louder): return await StreamReplies.changeVolume(louder: louder)
        }
    }

    private func play(_ requested: String?) async -> String {
        let defaults = UserDefaults.standard
        guard let name = requested ?? defaults.string(forKey: Self.lastStationKey) else {
            return String(localized: "Hangi radyoyu açayım? Örneğin Power FM, TRT FM ya da Virgin Radio diyebilirsin.")
        }
        if requested == nil, let address = defaults.url(forKey: Self.lastStationURLKey),
           await StreamPlayer.shared.play(.init(kind: .radio, title: name, show: nil, url: address)) {
            await MusicPlayers.pauseAll()
            return String(localized: "\(name) çalıyor.")
        }
        do {
            let stations = try await RadioBrowser.stations(named: name)
            guard !stations.isEmpty else { return ToolReply.failure(String(localized: "'\(name)' adında bir radyo bulamadım.")) }
            for station in stations.prefix(Self.candidatesToTry) {
                guard let url = station.streamURL else { continue }
                if await StreamPlayer.shared.play(.init(kind: .radio, title: name, show: nil, url: url)) {
                    await MusicPlayers.pauseAll()
                    defaults.set(name, forKey: Self.lastStationKey)
                    defaults.set(url, forKey: Self.lastStationURLKey)
                    return String(localized: "\(name) çalıyor.")
                }
            }
            return ToolReply.failure(String(localized: "\(name) yayınına bağlanamadım; istasyon şu an yayın yapmıyor olabilir."))
        } catch {
            return ToolReply.failure(String(localized: "Radyo listesine ulaşamadım. \(error.localizedDescription)"))
        }
    }

    /// A bare "devam et" is the music's when Music or Spotify holds a track, not a stream paused long ago.
    private func resume() async throws -> String {
        let stream = await StreamPlayer.shared.state
        guard await StreamMediaChoice.takes(pausing: false, stream: stream, subject: .unnamed,
                                            musicHoldsTrack: MusicPlayers.holdsTrack) else {
            return try await MediaTool().call(arguments: .init(action: .play, seconds: nil, subject: .music))
        }
        return await StreamReplies.resume()
    }
}

/// radio-browser.info's station search; its servers are mirrors, so the next is asked when one fails.
enum RadioBrowser {
    private static let servers = ["de1.api.radio-browser.info", "de2.api.radio-browser.info"]
    private static let resultLimit = 40

    /// Stations in Türkiye first; a name found nowhere there is looked for worldwide.
    static func stations(named name: String) async throws -> [RadioStation] {
        let local = RadioStationChoice.ranked(try await search(name, countryCode: "TR"), for: name)
        if !local.isEmpty { return local }
        return RadioStationChoice.ranked(try await search(name, countryCode: nil), for: name)
    }

    private static func search(_ name: String, countryCode: String?) async throws -> [RadioStation] {
        var lastError: (any Error)?
        for server in servers {
            var components = URLComponents()
            components.scheme = "https"
            components.host = server
            components.path = "/json/stations/search"
            components.queryItems = [
                .init(name: "name", value: name), .init(name: "hidebroken", value: "true"), .init(name: "order", value: "votes"),
                .init(name: "reverse", value: "true"), .init(name: "limit", value: String(resultLimit)),
            ] + (countryCode.map { [.init(name: "countrycode", value: $0)] } ?? [])
            guard let url = components.url else { continue }
            do {
                return RadioStation.list(from: try await WebFetch.data(from: url))
            } catch is CancellationError {
                throw CancellationError()
            } catch {
                Log.tools.error("radio-browser \(server, privacy: .public) failed: \(error.localizedDescription, privacy: .public)")
                lastError = error
            }
        }
        throw lastError ?? WebFetchError.unreachable
    }
}

/// What radio and podcast commands, and the media commands, say about the in-app player.
@MainActor
enum StreamReplies {
    static var nothingPlaying: String { String(localized: "Şu an çalan bir radyo ya da podcast yok.") }
    static var noPodcastOpen: String {
        ToolReply.failure(String(localized: "Açık bir podcast yok. Örneğin 'Mesele Ekonomi podcastinin son bölümünü aç' diyebilirsin."))
    }

    /// A station is turned off; an episode is paused, so it can go on later.
    static func stop() -> String {
        let player = StreamPlayer.shared
        guard let item = player.current else { return nothingPlaying }
        if item.kind == .radio {
            player.stop()
            return String(localized: "Radyoyu kapattım.")
        }
        player.pause()
        return String(localized: "Podcast'i duraklattım.")
    }

    static func pause() -> String {
        let player = StreamPlayer.shared
        guard let item = player.current else { return nothingPlaying }
        player.pause()
        return item.kind == .radio ? String(localized: "Radyoyu duraklattım.") : String(localized: "Podcast'i duraklattım.")
    }

    static func resume() -> String {
        let player = StreamPlayer.shared
        guard let item = player.current else { return nothingPlaying }
        if player.state == .playing {
            return item.kind == .radio ? String(localized: "\(item.title) zaten çalıyor.") : String(localized: "Podcast zaten çalıyor.")
        }
        player.resume()
        return item.kind == .radio ? String(localized: "\(item.title) yeniden çalıyor.") : String(localized: "Podcast'e devam ediyorum.")
    }

    static func nowPlaying() -> String {
        let player = StreamPlayer.shared
        guard let item = player.current else { return nothingPlaying }
        let name = item.show.map { "\($0): \(item.title)" } ?? item.title
        return player.state == .playing ? String(localized: "\(name) çalıyor.") : String(localized: "\(name) duraklatılmış.")
    }

    static func changeVolume(louder: Bool) -> String {
        let player = StreamPlayer.shared
        guard let item = player.current else { return ToolReply.failure(nothingPlaying) }
        let level = player.changeVolume(louder: louder)
        return item.kind == .radio
            ? String(localized: "Radyonun sesi yüzde \(level).")
            : String(localized: "Podcast'in sesi yüzde \(level).")
    }

    static func seek(by seconds: Int) -> String {
        guard StreamPlayer.shared.seek(by: seconds) else {
            return ToolReply.failure(String(localized: "Canlı radyo yayınında ileri ya da geri saramam."))
        }
        let spoken = Duration.seconds(abs(seconds)).spoken
        return seconds > 0 ? String(localized: "\(spoken) ileri sardım.") : String(localized: "\(spoken) geri sardım.")
    }
}
