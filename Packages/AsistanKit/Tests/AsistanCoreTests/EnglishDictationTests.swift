import Testing
@testable import AsistanCore

@Suite("English dictation")
struct EnglishDictationTests {
    @Test("whole-utterance controls", arguments: [
        ("New line", DictationCommand?.some(.newLine)), ("New paragraph", .newParagraph), ("Scratch that", .deleteLast),
        ("Delete the last sentence", .deleteLast), ("Stop dictation", .finish), ("I'm done", .finish),
        ("Delete that file from my desktop", nil), ("A new line of products", nil),
    ])
    func commands(text: String, expected: DictationCommand?) {
        #expect(DictationCommand.parse(text, language: .english) == expected)
    }

    @Test("starting dictation")
    func start() {
        #expect(DictationCommand.isStart("Start dictation", language: .english))
        #expect(DictationCommand.isStart("Turn on dictation mode", language: .english))
        #expect(!DictationCommand.isStart("Start the timer", language: .english))
    }

    @Test("spoken punctuation and capitals")
    func format() {
        #expect(DictationText.format("hello comma how are you question mark", after: nil, language: .english)
            == "Hello, how are you?")
        #expect(DictationText.format("it is ready period", after: "Okay.", language: .english) == " It is ready.")
        #expect(DictationText.format("i think so", after: nil, language: .english) == "I think so")
        #expect(DictationText.format("see you open quote soon close quote", after: "Bye", language: .english)
            == " see you \"soon\"")
    }
}
