import Foundation
import Testing
@testable import AsistanCore

@Suite("Release check")
struct ReleaseCheckTests {
    private let page = "https://github.com/coderssociety/bilge-assistant/releases/tag/v0.3.0"

    @Test("versions compare", arguments: [
        ("v0.3.0", "0.2.0", true), ("0.2.1", "0.2.0", true), ("v0.3.0", "0.3.0-rc1", true), ("v0.2.0", "0.2.0", false),
        ("v0.2", "0.2.0", false), ("v0.1.0", "0.2.0", false), ("v1.0.0-rc2", "1.0.0-rc1", true), ("nightly", "0.1.0", false),
        ("v0.3.0", "dev", false),
    ])
    func compares(published: String, running: String, newer: Bool) {
        #expect(ReleaseCheck.isNewer(published, than: running) == newer)
    }

    @Test("reads GitHub's answer")
    func readsTheAnswer() throws {
        let data = Data(#"{"tag_name": "v0.3.0", "html_url": "\#(page)", "draft": false}"#.utf8)
        #expect(try ReleaseCheck.latest(from: data) == .init(version: "0.3.0", page: URL(string: page)!))
    }

    @Test("keeps the release's own files and finds the Mac package and the checksums")
    func readsTheFiles() throws {
        let base = "https://github.com/coderssociety/bilge-assistant/releases/download/v0.6.0/"
        let data = Data("""
        {"tag_name": "v0.6.0", "html_url": "https://github.com/coderssociety/bilge-assistant/releases/tag/v0.6.0", "assets": [
          {"name": "Bilge-0.6.0.dmg", "browser_download_url": "\(base)Bilge-0.6.0.dmg"},
          {"name": "SHA256SUMS", "browser_download_url": "\(base)SHA256SUMS"},
          {"name": "Bilge-Setup-0.6.0.exe", "browser_download_url": "https://example.com/Bilge-Setup-0.6.0.exe"}
        ]}
        """.utf8)
        let release = try ReleaseCheck.latest(from: data)
        #expect(release.assets.map(\.name) == ["Bilge-0.6.0.dmg", "SHA256SUMS"])
        #expect(release.macPackage?.url.absoluteString == base + "Bilge-0.6.0.dmg")
        #expect(release.checksums?.name == "SHA256SUMS")
    }

    @Test("a release remembered before files were kept still decodes")
    func oldRecord() throws {
        let old = Data(#"{"version": "0.5.0", "page": "https://github.com/coderssociety/bilge-assistant/releases/tag/v0.5.0"}"#.utf8)
        let release = try JSONDecoder().decode(ReleaseCheck.Release.self, from: old)
        #expect(release.assets.isEmpty && release.macPackage == nil)
    }

    @Test("only this project's downloads pass", arguments: [
        ("https://github.com/coderssociety/bilge-assistant/releases/download/v0.6.0/Bilge-0.6.0.dmg", true),
        ("https://github.com/coderssociety/bilge-assistant/releases/download/../../evil/x.dmg", false),
        ("https://github.com/coderssociety/other/releases/download/v1/x.dmg", false),
        ("http://github.com/coderssociety/bilge-assistant/releases/download/v1/x.dmg", false),
        ("https://objects.githubusercontent.com/x.dmg", false),
    ])
    func projectDownloads(url: String, accepted: Bool) {
        #expect(ReleaseCheck.isProjectDownload(URL(string: url)!) == accepted)
    }

    @Test("reads a SHA256SUMS file")
    func checksums() {
        let hash = String(repeating: "ab", count: 32)
        let text = "\(hash)  Bilge-0.6.0.dmg\n\(hash.uppercased()) *Bilge-Setup-0.6.0.exe\nnot a line\nabc  short.txt\n"
        #expect(ReleaseCheck.checksums(in: text) == ["Bilge-0.6.0.dmg": hash, "Bilge-Setup-0.6.0.exe": hash])
    }

    @Test("refuses a page outside the project and malformed answers")
    func refusesStrangeAnswers() {
        let foreign = Data(#"{"tag_name": "v9.0.0", "html_url": "https://example.com/bilge.dmg"}"#.utf8)
        #expect(throws: ReleaseCheck.Failure.foreignPage("https://example.com/bilge.dmg")) { try ReleaseCheck.latest(from: foreign) }
        for body in [#"{"tag_name": "v1.0.0"}"#, "[1, 2]", #"{"tag_name": "latest", "html_url": "\#(page)"}"#, "not json"] {
            #expect(throws: ReleaseCheck.Failure.unexpectedAnswer) { try ReleaseCheck.latest(from: Data(body.utf8)) }
        }
    }

    @Test("only this project's release pages pass", arguments: [
        ("https://github.com/coderssociety/bilge-assistant/releases/tag/v0.3.0", true),
        ("https://github.com/coderssociety/bilge-assistant/releases/../../evil/repo", false),
        ("https://github.com/coderssociety/bilge-assistant/releases/%2e%2e/%2e%2e/evil", false),
        ("https://github.com.evil.example/coderssociety/bilge-assistant/releases/x", false),
        ("http://github.com/coderssociety/bilge-assistant/releases/tag/v1", false),
        ("https://user@github.com/coderssociety/bilge-assistant/releases/tag/v1", false),
    ])
    func projectPages(page: String, accepted: Bool) {
        #expect(ReleaseCheck.isProjectPage(URL(string: page)!) == accepted)
    }

    @Test("digits other than ASCII are not a version")
    func asciiOnly() {
        #expect(!ReleaseCheck.isNewer("v١.٠", than: "0.1"))
        #expect(!ReleaseCheck.isNewer("v99999999999999999999999.0", than: "0.1"))
    }

    @Test("asks once a day, and again when the clock went back")
    func daily() {
        let now = Date(timeIntervalSince1970: 2_000_000_000)
        #expect(ReleaseCheck.isDue(lastChecked: nil, now: now))
        #expect(!ReleaseCheck.isDue(lastChecked: now.addingTimeInterval(-23 * 3600), now: now))
        #expect(ReleaseCheck.isDue(lastChecked: now.addingTimeInterval(-25 * 3600), now: now))
        #expect(ReleaseCheck.isDue(lastChecked: now.addingTimeInterval(7 * 24 * 3600), now: now))
    }
}
