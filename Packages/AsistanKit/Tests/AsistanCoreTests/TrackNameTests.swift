import Testing
@testable import AsistanCore

@Suite("Track names")
struct TrackNameTests {
    @Test("site names, counters and video labels go; an artist the title says is not repeated", arguments: [
        ("(3) TARKAN - Kuzu Kuzu (Official Music Video) - YouTube", "TarkanVEVO", "TARKAN - Kuzu Kuzu", ""),
        ("Begonvil - YouTube Music", "Sezen Aksu", "Begonvil", "Sezen Aksu"),
        ("Kuzu Kuzu - Deezer", "Tarkan", "Kuzu Kuzu", "Tarkan"),
        ("Gidiyorum [Sözleri]", "Sezen Aksu - Topic", "Gidiyorum", "Sezen Aksu"),
        ("Gesi Bağları", "Zeki Müren", "Gesi Bağları", "Zeki Müren"),
        ("YouTube", "", "YouTube", ""),
    ])
    func cleaned(title: String, artist: String, expectedTitle: String, expectedArtist: String) {
        let name = TrackName.cleaned(title, artist: artist)
        #expect(name.title == expectedTitle)
        #expect(name.artist == expectedArtist)
    }

    @Test("what a music tab plays, from its title", arguments: [
        ("(1) Sezen Aksu - Gidiyorum (Official Video) - YouTube", "Sezen Aksu - Gidiyorum"),
        ("Kuzu Kuzu - Tarkan | Deezer", "Kuzu Kuzu - Tarkan"),
        ("Begonvil - YouTube Music", "Begonvil"),
    ])
    func tab(title: String, expected: String) {
        #expect(TrackName.fromTab(title) == expected)
    }

    @Test("a tab showing only the site or an idle player plays nothing", arguments: [
        "YouTube", "YouTube Music", "Spotify – Web Player: Music for everyone", "  ",
    ])
    func idleTab(title: String) {
        #expect(TrackName.fromTab(title) == nil)
    }
}
