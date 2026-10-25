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
        ("Summarize the PDF I downloaded last", "files", "readDocument"),
        ("What does my latest download say", "files", "readDocument"),
    ])
    func corrects(command: String, action: String, expected: String) {
        #expect(EnglishRouteGuard.review(action: action, command: command) == expected)
    }

    @Test("leaves right decisions alone", arguments: [
        ("Remind me in 20 minutes to take the laundry out", "setTimer"),
        ("Wake me up at 7", "setTimer"),
        ("Search YouTube for cat videos", "searchWeb"),
        ("Lock the screen", "systemAction"),
        ("Turn off the display", "systemAction"),
        ("Blank the screen", "systemAction"),
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
        ("Open the PDF I downloaded last", "files"),
    ])
    func keeps(command: String, action: String) {
        #expect(EnglishRouteGuard.review(action: action, command: command) == action)
    }

    @Test("gold goes to its own prices, currencies stay with the rates", arguments: [
        ("how much is gold", "exchangeRate", "goldPrice"),
        ("convert fifty dollars to euros", "exchangeRate", "exchangeRate"),
    ])
    func gold(command: String, routed: String, expected: String) {
        #expect(EnglishRouteGuard.review(action: routed, command: command) == expected)
    }

    @Test("encyclopedic questions go to Wikipedia, small talk does not", arguments: [
        ("who was Ada Lovelace", "conversation", "wikipedia"),
        ("what is photosynthesis", "conversation", "wikipedia"),
        ("how are you", "conversation", "conversation"),
        ("who are you", "conversation", "conversation"),
        ("what is the capital of France", "conversation", "conversation"),
        ("what does the screen say", "readScreen", "readScreen"),
    ])
    func wikipedia(command: String, routed: String, expected: String) {
        #expect(EnglishRouteGuard.review(action: routed, command: command) == expected)
    }
}
