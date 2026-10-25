import Foundation

/// A track's title and artist as they are worth saying: a browser tab's "(3) TARKAN - Kuzu Kuzu (Official Music
/// Video) - YouTube" is "TARKAN - Kuzu Kuzu", and an artist already in the title is not said twice.
public enum TrackName {
    private static let siteNames = ["YouTube Music", "YouTube", "Deezer", "Spotify", "Apple Music", "SoundCloud"]
    private static let counter = try! NSRegularExpression(pattern: #"^\(\d+\)\s+"#)
    private static let site = try! NSRegularExpression(
        pattern: #"\s+[-–—|·•]\s+(\#(siteNames.joined(separator: "|")))\s*$"#, options: .caseInsensitive)
    private static let labels = try! NSRegularExpression(
        pattern: #"\s*[(\[][^)\]]*\b(official|video|audio|lyrics?|klip|clip|sözleri|sozleri|hd|4k|visuali[sz]er)\b[^)\]]*[)\]]"#,
        options: .caseInsensitive)
    private static let channelSuffix = try! NSRegularExpression(pattern: #"(\s+-\s+(Topic|Konu)|VEVO)$"#)
    /// Spotify's tab when nothing is playing: "Spotify – Web Player: Music for everyone".
    private static let idlePages = ["web player"]

    /// The title without site names and video labels, and the artist, empty when the title already says it.
    public static func cleaned(_ title: String, artist: String = "") -> (title: String, artist: String) {
        let trimmedTitle = title.trimmingCharacters(in: .whitespaces)
        let name = removing(labels, from: removing(site, from: removing(counter, from: trimmedTitle)))
            .trimmingCharacters(in: .whitespaces)
        var by = removing(channelSuffix, from: artist.trimmingCharacters(in: .whitespaces)).trimmingCharacters(in: .whitespaces)
        if !by.isEmpty, TurkishText.folded(name).contains(TurkishText.folded(by)) { by = "" }
        return (name.isEmpty ? trimmedTitle : name, by)
    }

    /// What a music tab plays, from its title; nil when the title is only the site's name or an idle page.
    public static func fromTab(_ title: String) -> String? {
        let name = cleaned(title).title
        let folded = TurkishText.folded(name)
        guard !name.isEmpty, !siteNames.contains(where: { TurkishText.folded($0) == folded }),
              !idlePages.contains(where: folded.contains) else { return nil }
        return name
    }

    /// "Artist – Title", or the title alone when there is no artist.
    public static func spoken(title: String, artist: String) -> String {
        artist.isEmpty ? title : "\(artist) – \(title)"
    }

    private static func removing(_ pattern: NSRegularExpression, from text: String) -> String {
        pattern.stringByReplacingMatches(in: text, range: NSRange(text.startIndex..., in: text), withTemplate: "")
    }
}
