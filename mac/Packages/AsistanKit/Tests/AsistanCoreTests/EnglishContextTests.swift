import Testing
@testable import AsistanCore

@Suite("English screen context")
struct EnglishContextTests {
    @Test("requests about what is on screen", arguments: [
        ("Summarize this", ContextIntent?.some(.init(action: .summarize, wanted: nil))),
        ("Translate the selected text", .init(action: .translate, wanted: .text)),
        ("What does this error mean", .init(action: .explain, wanted: nil)),
        ("Open this file", .init(action: .open, wanted: .file)),
        ("Read this page to me", .init(action: .read, wanted: .page)),
        ("Give me a summary of this article", .init(action: .summarize, wanted: .page)),
        ("Explain the highlighted paragraph", .init(action: .explain, wanted: .text)),
        ("What's on this evening", nil),
        ("Play this song", nil),
        ("Open Safari", nil),
    ])
    func parse(command: String, expected: ContextIntent?) {
        #expect(ContextIntent.parse(command, language: .english) == expected)
    }

    @Test("pointing")
    func points() {
        #expect(ContextIntent.points("Send this to Ahmet", language: .english))
        #expect(!ContextIntent.points("What are you doing this weekend", language: .english))
        #expect(!ContextIntent.points("Send Ahmet a message", language: .english))
    }

    @Test("message bodies that only point")
    func onlyPoints() {
        #expect(ContextIntent.onlyPoints("this", language: .english))
        #expect(ContextIntent.onlyPoints("that link", language: .english))
        #expect(ContextIntent.onlyPoints("the file", language: .english) == false)
        #expect(!ContextIntent.onlyPoints("I'll be late", language: .english))
        #expect(ContextIntent.wantedKind(in: "this link", language: .english) == .page)
    }
}
