import Testing
@testable import AsistanCore

@Suite("EnglishRouteGuard")
struct EnglishRouteGuardTests {
    @Test("corrects known confusions", arguments: [
        ("Type see you tomorrow", "setTimer", "typeText"),
        ("Remind me to pay rent on Monday", "setTimer", "addReminder"),
        ("Remind me to call mom", "setTimer", "addReminder"),
        ("Don't forget the meeting tomorrow", "setTimer", "addReminder"),
        ("Turn on do not disturb", "systemAction", "runShortcut"),
        ("Make the screen brighter", "systemAction", "runShortcut"),
        ("What is the capital of Australia", "searchWeb", "conversation"),
        ("Copy your last answer", "readClipboard", "copyToClipboard"),
        ("Next song", "playMusic", "controlMusic"),
        ("How much is 15 percent of 240", "conversation", "calculate"),
        ("Translate the selected text to Turkish", "conversation", "readSelection"),
        ("Give me some advice", "weather", "conversation"),
        ("Open Calendar", "readCalendar", "openApp"),
        ("Stop the timer", "setTimer", "manageTimers"),
        ("Stop the timer", "controlMusic", "manageTimers"),
        ("Jot down: buy a birthday gift for Ece", "readWebPage", "createNote"),
        ("Make a note that the plumber comes Tuesday", "addReminder", "createNote"),
        ("Close all Finder windows", "quitApp", "windowControl"),
    ])
    func corrects(command: String, action: String, expected: String) {
        #expect(EnglishRouteGuard.review(action: action, command: command) == expected)
    }

    @Test("leaves right decisions alone", arguments: [
        ("Remind me in 20 minutes to take the laundry out", "setTimer"),
        ("Wake me up at 7", "setTimer"),
        ("Search YouTube for cat videos", "searchWeb"),
        ("Lock the screen", "systemAction"),
        ("Turn on dark mode", "systemAction"),
        ("What's on my clipboard", "readClipboard"),
        ("Play some relaxing jazz", "playMusic"),
        ("Who wrote Hamlet", "conversation"),
        ("Will it be sunny tomorrow", "weather"),
        ("What's on my calendar today", "readCalendar"),
        ("What type of music do you like", "conversation"),
        ("Set an alarm for 6:30", "setTimer"),
        ("Quit Preview", "quitApp"),
        ("Set a timer for 10 minutes", "setTimer"),
        ("Note the time", "conversation"),
    ])
    func keeps(command: String, action: String) {
        #expect(EnglishRouteGuard.review(action: action, command: command) == action)
    }
}
