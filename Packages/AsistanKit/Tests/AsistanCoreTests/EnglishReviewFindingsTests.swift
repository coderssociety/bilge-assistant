import Foundation
import Testing
@testable import AsistanCore

/// Cases a review found: each English rule must leave ordinary requests alone and never read hesitation as yes.
@Suite("English review findings")
struct EnglishReviewFindingsTests {
    @Test("hesitation is not a yes", arguments: ["I'm not sure", "not ok", "not yet", "please wait", "hold on", "maybe later"])
    func hesitation(text: String) {
        #expect(ConfirmationParser.parse(text, language: .english) != .confirmed)
    }

    @Test("browser rules leave ordinary commands alone", arguments: [
        "volume up", "volume down", "shut down", "what's up", "forward it to Sam", "call me back", "top stories",
        "turn it up",
    ])
    func browser(text: String) {
        #expect(BrowserCommand.parse(text, language: .english) == nil)
    }

    @Test("screen context only when the pointer is the object")
    func context() {
        #expect(!ContextIntent.points("Tell Ali that I'm late", language: .english))
        #expect(ContextIntent.points("Send this to Ali", language: .english))
        #expect(ContextIntent.points("What does this link say", language: .english))
        #expect(ContextIntent.parse("Remind me to read this", language: .english) == nil)
        #expect(ContextIntent.parse("Open this evening's calendar", language: .english) == nil)
    }

    @Test("route guard overrides only when sure", arguments: [
        ("Remind me to turn off the oven timer", "setTimer", "addReminder"),
        ("Copy the highlighted text", "copyToClipboard", "copyToClipboard"),
        ("Send the selected text to Ali", "sendMessage", "sendMessage"),
        ("Show my calendar", "readCalendar", "readCalendar"),
        ("Write Ali I'm here", "sendMessage", "sendMessage"),
    ])
    func guardKeeps(command: String, action: String, expected: String) {
        #expect(EnglishRouteGuard.review(action: action, command: command) == expected)
    }

    @Test("a reminder's content is not split into commands")
    func compound() {
        #expect(CompoundCommand.split("Remind me to call the bank and send the invoice", language: .english) == nil)
        #expect(CompoundCommand.split("Open Safari and then set the volume to 30", language: .english)
            == ["Open Safari", "set the volume to 30"])
    }

    @Test("dictation off is not a start")
    func dictation() {
        #expect(!DictationCommand.isStart("Turn off dictation", language: .english))
        #expect(DictationCommand.parse("Turn off dictation", language: .english) == .finish)
    }

    @Test("dictated stop words are text inside a work session")
    func workSession() {
        var flow = ConversationFlow(matcher: WakePhraseMatcher(phrase: "bilge"))
        let now = Date()
        _ = flow.heard("Bilge start dictation", at: now)
        flow.responseFinished(at: now, allowFollowUp: true, session: .init(window: 60) { _ in true })
        #expect(flow.heard("Nothing.", at: now.addingTimeInterval(1)) == .runWorkInput("Nothing."))
    }

    @Test("English durations", arguments: [
        ("twenty five minutes", 1500), ("ninety minutes", 5400), ("an hour and a half", 5400), ("seventeen seconds", 17),
    ])
    func durations(text: String, seconds: Int) {
        #expect(EnglishTimeParser.parse(text)?.durationSeconds == seconds)
    }

    @Test("what is a cell reads it")
    func read() {
        #expect(SpreadsheetCommand.parse("What is B2", language: .english) == .read(CellReference("B2")!))
    }
}
