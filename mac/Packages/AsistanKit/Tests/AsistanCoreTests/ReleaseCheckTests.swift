import Foundation
import Testing
@testable import AsistanCore

@Suite("Release check")
struct ReleaseCheckTests {
    private let page = "https://github.com/coderssociety/bilge/releases/tag/v0.3.0"

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

    @Test("refuses a page outside the project and malformed answers")
    func refusesStrangeAnswers() {
        let foreign = Data(#"{"tag_name": "v9.0.0", "html_url": "https://example.com/bilge.dmg"}"#.utf8)
        #expect(throws: ReleaseCheck.Failure.foreignPage("https://example.com/bilge.dmg")) { try ReleaseCheck.latest(from: foreign) }
        for body in [#"{"tag_name": "v1.0.0"}"#, "[1, 2]", #"{"tag_name": "latest", "html_url": "\#(page)"}"#, "not json"] {
            #expect(throws: ReleaseCheck.Failure.unexpectedAnswer) { try ReleaseCheck.latest(from: Data(body.utf8)) }
        }
    }

    @Test("only this project's release pages pass", arguments: [
        ("https://github.com/coderssociety/bilge/releases/tag/v0.3.0", true),
        ("https://github.com/coderssociety/bilge/releases/../../evil/repo", false),
        ("https://github.com/coderssociety/bilge/releases/%2e%2e/%2e%2e/evil", false),
        ("https://github.com.evil.example/coderssociety/bilge/releases/x", false),
        ("http://github.com/coderssociety/bilge/releases/tag/v1", false),
        ("https://user@github.com/coderssociety/bilge/releases/tag/v1", false),
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
