import AVFoundation
import AsistanCore

/// Radio streams and podcast episodes played inside Bilge. While Bilge listens or speaks, radio drops to a fifth of
/// its volume and a podcast pauses, so nothing is missed; both come back when the turn is over.
@MainActor
final class StreamPlayer {
    enum Kind: Sendable, Equatable {
        case radio, podcast
    }

    struct Item: Sendable, Equatable {
        let kind: Kind
        /// The station, or the episode.
        let title: String
        /// The podcast an episode belongs to.
        let show: String?
        let url: URL
    }

    static let shared = StreamPlayer()
    private static let duckedShare: Float = 0.2
    private static let volumeStep: Float = 0.2
    private static let quietestVolume: Float = 0.1
    private static let readyTimeout: Duration = .seconds(10)
    private static let readyPoll: Duration = .milliseconds(100)

    private let player = AVPlayer()
    private(set) var current: Item?
    /// The user's intent; a podcast held for Bilge's turn still wants to play.
    private var wantsPlayback = false
    private var isDucked = false
    private(set) var volume: Float = 1
    private var endObservers: [any NSObjectProtocol] = []

    var state: StreamState {
        guard current != nil else { return .idle }
        return wantsPlayback ? .playing : .paused
    }

    /// Only http(s) streams whose redirects and addresses are all public, played from where the redirects end;
    /// addresses come from radio-browser and podcast feeds.
    static func allowedURL(_ url: URL) async -> URL? {
        do {
            return try await WebFetch.mediaURL(for: url)
        } catch {
            Log.tools.error("Refused to play a stream: \(error.localizedDescription, privacy: .public)")
            return nil
        }
    }

    /// Starts `item` and waits until the stream answers; false (and nothing playing) if it could not be played.
    func play(_ item: Item) async -> Bool {
        guard let url = await Self.allowedURL(item.url) else { return false }
        let playerItem = load(url)
        current = Item(kind: item.kind, title: item.title, show: item.show, url: url)
        wantsPlayback = true
        apply()
        let ready = await waitUntilReady(playerItem)
        if !ready, player.currentItem === playerItem {
            Log.tools.error("Stream did not start: \(playerItem.error?.localizedDescription ?? "timed out", privacy: .public)")
            stop()
        }
        return ready
    }

    func pause() {
        guard current != nil else { return }
        wantsPlayback = false
        apply()
    }

    /// A live stream starts again from now rather than from where it was paused.
    func resume() {
        guard let current else { return }
        if current.kind == .radio { load(current.url) }
        wantsPlayback = true
        apply()
    }

    func stop() {
        removeEndObservers()
        player.replaceCurrentItem(with: nil)
        current = nil
        wantsPlayback = false
    }

    /// Only an episode can be skipped through; false for a live stream.
    func seek(by seconds: Int) -> Bool {
        guard current?.kind == .podcast, let item = player.currentItem else { return false }
        var target = max(0, player.currentTime().seconds + Double(seconds))
        let duration = item.duration.seconds
        if duration.isFinite, duration > 0 { target = min(target, duration - 1) }
        player.seek(to: CMTime(seconds: target, preferredTimescale: 600))
        return true
    }

    /// Returns the new volume as a percentage of full.
    func changeVolume(louder: Bool) -> Int {
        volume = min(1, max(Self.quietestVolume, volume + (louder ? Self.volumeStep : -Self.volumeStep)))
        apply()
        return Int((volume * 100).rounded())
    }

    func setDucked(_ ducked: Bool) {
        guard ducked != isDucked else { return }
        isDucked = ducked
        apply()
    }

    @discardableResult
    private func load(_ url: URL) -> AVPlayerItem {
        removeEndObservers()
        let item = AVPlayerItem(url: url)
        player.replaceCurrentItem(with: item)
        // A finished episode or a stream that broke off leaves nothing playing.
        for name in [AVPlayerItem.didPlayToEndTimeNotification, AVPlayerItem.failedToPlayToEndTimeNotification] {
            endObservers.append(NotificationCenter.default.addObserver(forName: name, object: item, queue: .main) { [weak self] _ in
                MainActor.assumeIsolated { self?.stop() }
            })
        }
        return item
    }

    private func removeEndObservers() {
        endObservers.forEach(NotificationCenter.default.removeObserver)
        endObservers = []
    }

    private func apply() {
        guard let current else {
            player.pause()
            return
        }
        let heldForBilge = isDucked && current.kind == .podcast
        if wantsPlayback, !heldForBilge { player.play() } else { player.pause() }
        player.volume = isDucked ? volume * Self.duckedShare : volume
    }

    private func waitUntilReady(_ item: AVPlayerItem) async -> Bool {
        let deadline = ContinuousClock.now + Self.readyTimeout
        while ContinuousClock.now < deadline, player.currentItem === item, item.status == .unknown, !Task.isCancelled {
            try? await Task.sleep(for: Self.readyPoll)
        }
        return item.status == .readyToPlay
    }
}
