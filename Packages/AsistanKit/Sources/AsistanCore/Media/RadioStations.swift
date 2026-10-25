import Foundation

/// A station as radio-browser.info lists it (`/json/stations/search`).
public struct RadioStation: Decodable, Equatable, Sendable {
    public let name: String
    public let streamURL: URL?
    public let codec: String
    public let votes: Int
    public let isHLS: Bool
    public let lastCheckOK: Bool

    public init(name: String, streamURL: URL?, codec: String, votes: Int, isHLS: Bool, lastCheckOK: Bool) {
        self.name = name
        self.streamURL = streamURL
        self.codec = codec
        self.votes = votes
        self.isHLS = isHLS
        self.lastCheckOK = lastCheckOK
    }

    private enum CodingKeys: String, CodingKey {
        case name, url, codec, votes, hls, lastcheckok
        case urlResolved = "url_resolved"
    }

    /// Every field is optional in practice: a station with a missing one is kept, and dropped only if it cannot play.
    public init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        name = (try? container.decode(String.self, forKey: .name))?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        let resolved = (try? container.decode(String.self, forKey: .urlResolved)).flatMap { $0.isEmpty ? nil : $0 }
        let address = resolved ?? (try? container.decode(String.self, forKey: .url))
        streamURL = address.flatMap { URL(string: $0.trimmingCharacters(in: .whitespacesAndNewlines)) }
        codec = (try? container.decode(String.self, forKey: .codec)) ?? ""
        votes = (try? container.decode(Int.self, forKey: .votes)) ?? 0
        isHLS = ((try? container.decode(Int.self, forKey: .hls)) ?? 0) == 1
        lastCheckOK = ((try? container.decode(Int.self, forKey: .lastcheckok)) ?? 1) == 1
    }

    public static func list(from data: Data) -> [RadioStation] {
        (try? JSONDecoder().decode([RadioStation].self, from: data)) ?? []
    }
}

/// Which of the stations a search returned to play for a spoken name.
public enum RadioStationChoice {
    private static let playableCodecs: Set<String> = ["mp3", "aac", "aac+", "he-aac", "mpeg"]

    private enum NameMatch: Int, Comparable {
        case exact, prefix, phrase, allWords

        static func < (lhs: NameMatch, rhs: NameMatch) -> Bool { lhs.rawValue < rhs.rawValue }
    }

    /// The stations worth trying, best first: those named most like `query`, then MP3/AAC or HLS over https,
    /// then the most voted. Stations whose name lacks any word of `query`, or that cannot play, are left out.
    public static func ranked(_ stations: [RadioStation], for query: String) -> [RadioStation] {
        let wanted = TurkishText.folded(query)
        guard !wanted.isEmpty else { return [] }
        let candidates = stations.compactMap { station -> (RadioStation, NameMatch)? in
            guard station.lastCheckOK, isPlayable(station), let match = match(TurkishText.folded(station.name), wanted) else {
                return nil
            }
            return (station, match)
        }
        return candidates.sorted { lhs, rhs in
            if lhs.1 != rhs.1 { return lhs.1 < rhs.1 }
            let (left, right) = (isSecure(lhs.0), isSecure(rhs.0))
            if left != right { return left }
            return lhs.0.votes > rhs.0.votes
        }.map(\.0)
    }

    private static func isPlayable(_ station: RadioStation) -> Bool {
        guard let scheme = station.streamURL?.scheme?.lowercased(), ["http", "https"].contains(scheme) else { return false }
        return station.isHLS || playableCodecs.contains(station.codec.lowercased())
    }

    private static func isSecure(_ station: RadioStation) -> Bool {
        station.streamURL?.scheme?.lowercased() == "https"
    }

    private static func match(_ name: String, _ wanted: String) -> NameMatch? {
        if name == wanted { return .exact }
        if name.hasPrefix(wanted + " ") { return .prefix }
        if (" " + name + " ").contains(" " + wanted + " ") { return .phrase }
        let words = Set(name.split(separator: " "))
        return wanted.split(separator: " ").allSatisfy(words.contains) ? .allWords : nil
    }
}

/// Popular Turkish stations by the names people say, with the name to search radio-browser for.
public enum PopularRadioStations {
    public struct Entry: Sendable, Equatable {
        public let name: String
        public let aliases: [String]
    }

    public static let all: [Entry] = [
        Entry(name: "Power FM", aliases: ["power fm"]),
        Entry(name: "Power Türk", aliases: ["power türk", "power turk fm", "power türk fm"]),
        Entry(name: "Power Pop", aliases: ["power pop"]),
        Entry(name: "TRT FM", aliases: ["trt fm", "te re te fm"]),
        Entry(name: "TRT Radyo 1", aliases: ["trt radyo 1", "trt radyo bir", "radyo 1", "radyo bir"]),
        Entry(name: "TRT Radyo Haber", aliases: ["trt radyo haber", "radyo haber"]),
        Entry(name: "TRT Türkü", aliases: ["trt türkü"]),
        Entry(name: "TRT Nağme", aliases: ["trt nağme"]),
        Entry(name: "Virgin Radio", aliases: ["virgin radio", "virgin radyo", "virgin"]),
        Entry(name: "Kral FM", aliases: ["kral fm", "kral"]),
        Entry(name: "Kral Pop", aliases: ["kral pop"]),
        Entry(name: "Kral Türk", aliases: ["kral türk", "kral türk fm"]),
        Entry(name: "Süper FM", aliases: ["süper fm", "super fm"]),
        Entry(name: "Joy FM", aliases: ["joy fm", "joy"]),
        Entry(name: "Joy Türk", aliases: ["joy türk", "joy türk fm"]),
        Entry(name: "Best FM", aliases: ["best fm"]),
        Entry(name: "Radyo Fenomen", aliases: ["radyo fenomen", "fenomen"]),
        Entry(name: "Metro FM", aliases: ["metro fm"]),
        Entry(name: "Alem FM", aliases: ["alem fm"]),
        Entry(name: "Show Radyo", aliases: ["show radyo"]),
        Entry(name: "Radyo Eksen", aliases: ["radyo eksen", "eksen"]),
        Entry(name: "Slow Türk", aliases: ["slow türk", "slow turk"]),
        Entry(name: "Pal FM", aliases: ["pal fm"]),
        Entry(name: "Radyo D", aliases: ["radyo d", "radyo de"]),
        Entry(name: "Kafa Radyo", aliases: ["kafa radyo"]),
        Entry(name: "Radyo 7", aliases: ["radyo 7", "radyo yedi"]),
    ]

    /// The entry whose alias is the whole of `phrase` (folded).
    public static func entry(named phrase: String) -> Entry? {
        let folded = TurkishText.folded(phrase)
        guard !folded.isEmpty else { return nil }
        return all.first { $0.aliases.contains { TurkishText.folded($0) == folded } }
    }

    public static func isKnown(_ phrase: String) -> Bool {
        entry(named: phrase) != nil
    }
}
