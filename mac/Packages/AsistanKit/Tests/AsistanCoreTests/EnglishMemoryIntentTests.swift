import Testing
@testable import AsistanCore

@Suite("English memory requests")
struct EnglishMemoryIntentTests {
    @Test("recognizes memory requests", arguments: [
        ("Remember that my wife's birthday is in May", MemoryIntent?.some(.remember)),
        ("Please remember I take my coffee black", .remember),
        ("Don't forget that the door code is 4512", .remember),
        ("Keep in mind that I'm vegetarian", .remember),
        ("What do you remember about me", .list),
        ("What do you know about me", .list),
        ("Show me your memory", .list),
        ("Forget that", .forget),
        ("Forget my coffee order", .forget),
        ("Clear your memory", .forget),
        ("Remind me to call mom", nil),
        ("Remind me tomorrow that I have to remember the keys", nil),
        ("What's the weather", nil),
        ("What's the Mac's memory usage", nil),
        ("How much memory is the computer using", nil),
        ("Don't forget the meeting tomorrow", nil),
        ("Don't forget that the meeting is tomorrow", .remember),
    ])
    func parse(command: String, expected: MemoryIntent?) {
        #expect(MemoryIntent.parse(command, language: .english) == expected)
    }

    @Test("extracts the fact", arguments: [
        ("Remember that my wife's birthday is in May", String?.some("my wife's birthday is in May")),
        ("Please remember: I take my coffee black.", "I take my coffee black"),
        ("Don't forget the door code is 4512", "the door code is 4512"),
        ("Remember this", nil),
        ("Remember that", nil),
    ])
    func fact(command: String, expected: String?) {
        #expect(MemoryIntent.fact(from: command, language: .english) == expected)
    }

    @Test("what to forget", arguments: [
        ("Forget everything", MemoryIntent.ForgetTarget.all),
        ("Clear your memory", .all),
        ("Forget it all", .all),
        ("Forget that", .latest),
        ("Forget my coffee order", .matching("my coffee order")),
        ("Please forget what I told you about the door code", .matching("door code")),
    ])
    func target(command: String, expected: MemoryIntent.ForgetTarget) {
        #expect(MemoryIntent.forgetTarget(from: command, language: .english) == expected)
    }
}
