/// English counterpart of `RouteGuard.review`: corrects routing confusions the model keeps making with
/// English requests (Focus read as "lock screen", knowledge questions sent to web search, typing or
/// other-day reminders set as timers).
public enum EnglishRouteGuard {
    private static let searchWords: Set<String> = [
        "search", "google", "look", "find", "youtube", "wikipedia", "web", "internet", "online", "maps", "browse",
    ]
    private static let systemWords = ["lock", "sleep", "dark", "light", "appearance", "theme", "screensaver", "blank"]
    private static let focusWords: Set<String> = ["focus", "disturb", "dnd"]
    private static let brightnessWords = ["bright", "dim"]
    private static let openVerbs: Set<String> = ["open", "launch", "start"]
    private static let questionWords: Set<String> = ["what", "whats", "any", "do", "how", "when", "is", "am", "anything"]
    private static let weatherWords = [
        "weather", "temperature", "degree", "hot", "cold", "warm", "rain", "snow", "wind", "sun", "cloud", "humid",
        "storm", "umbrella", "jacket", "coat", "forecast", "fog", "frost", "chilly",
    ]
    private static let otherDayWords: Set<String> = [
        "tomorrow", "monday", "tuesday", "wednesday", "thursday", "friday", "saturday", "sunday", "next", "week",
        "weekend",
    ]
    private static let timeWords = ["second", "minute", "hour", "morning", "evening", "noon", "tonight", "pm", "am", "oclock"]
    private static let mathWords: Set<String> = [
        "plus", "minus", "times", "multiplied", "divided", "percent", "squared", "cubed", "root",
    ]
    private static let playbackWords: Set<String> = ["next", "previous", "skip", "pause", "resume", "rewind", "shuffle"]
    private static let selectionWords: Set<String> = ["selected", "highlighted", "selection"]
    private static let stopWords: Set<String> = ["stop", "cancel", "delete", "clear", "remove", "turn"]
    private static let readWords: Set<String> = ["read", "summarize", "summarise", "say", "says", "content", "contents"]

    public static func review(action: String, command: String, previousAction: String? = nil) -> String {
        let words = TurkishText.folded(command).split(separator: " ").map(String.init)
        if NoteRequest.addition(in: command, language: .english) != nil { return "appendToNote" }
        if NoteRequest.asksForList(command, language: .english) { return "readNotes" }
        if CallRequest.parse(command, language: .english) != nil { return "callContact" }
        if let calendarAction = CalendarChange.reviewedAction(action, command: command, language: .english) { return calendarAction }
        if MailReplyRequest.parse(command, language: .english) != nil,
           previousAction == "readMail" || MailReplyRequest.mentionsMail(command, language: .english) {
            return "replyMail"
        }
        // "Type see you tomorrow" was read as a timer because of "tomorrow".
        if isDictation(words), action != "createNote" { return "typeText" }
        // Only answers about the selection; copying or sending it keeps its own action.
        if words.contains(where: selectionWords.contains), ["conversation", "readScreen", "searchWeb"].contains(action) {
            return "readSelection"
        }
        if stopsTimer(words), action != "manageTimers" { return "manageTimers" }
        if takesNote(words), action != "createNote" { return "createNote" }
        if let control = macControl(action: action, words: words, command: command) { return control }
        switch action {
        case "quitApp" where words.contains { $0.hasPrefix("window") }:
            return "windowControl"
        case "setTimer":
            // Timers live in the app and fire only today.
            let reminds = words.contains { $0.hasPrefix("remind") || $0 == "forget" }
            let otherDay = words.contains(where: otherDayWords.contains)
            let hasTime = words.contains { word in word.contains(where: \.isNumber) || timeWords.contains(where: word.hasPrefix) }
            return reminds && (otherDay || !hasTime) ? "addReminder" : action
        case "searchWeb":
            return words.contains(where: searchWords.contains) ? action : "conversation"
        case "systemAction":
            let turnsScreenOff = words.contains { ["screen", "display", "monitor"].contains($0) } && words.contains("off")
            let supported = turnsScreenOff || words.contains { word in systemWords.contains(where: word.hasPrefix) }
                || MacControlRequest.power(command, language: .english) != nil
            return supported ? action : "runShortcut"
        case "weather":
            let aboutWeather = words.contains { word in weatherWords.contains(where: word.hasPrefix) }
            return aboutWeather || previousAction == action ? action : "conversation"
        case "openApp":
            let searches = words.contains { $0 == "search" || $0 == "find" } && words.contains(where: searchWords.contains)
            return searches ? "searchWeb" : action
        case "files":
            return words.contains(where: readWords.contains) ? "readDocument" : action
        case "readCalendar":
            let opensApp = words.first.map(openVerbs.contains) == true && !words.contains(where: questionWords.contains)
            return opensApp ? "openApp" : action
        case "readClipboard":
            return words.first == "copy" ? "copyToClipboard" : action
        case "playMusic":
            return words.contains(where: playbackWords.contains) ? "controlMusic" : action
        case "conversation":
            let isArithmetic = words.contains { $0.contains(where: \.isNumber) } && words.contains(where: mathWords.contains)
            if isArithmetic { return "calculate" }
            return EncyclopediaQuestion.subject(in: command, language: .english) != nil ? "wikipedia" : action
        case "exchangeRate":
            return words.contains { $0 == "gold" || $0 == "ounce" } ? "goldPrice" : action
        default:
            return action
        }
    }

    /// Focus, brightness, Bluetooth and power have their own actions; a named shortcut stays a shortcut.
    private static func macControl(action: String, words: [String], command: String) -> String? {
        guard ["runShortcut", "systemAction", "setWiFi", "quitApp", "openApp"].contains(action),
              !words.contains(where: { $0.hasPrefix("shortcut") || $0.hasPrefix("setting") }) else { return nil }
        if words.contains(where: { word in brightnessWords.contains(where: word.hasPrefix) }) { return "setBrightness" }
        if words.contains("bluetooth") { return "setBluetooth" }
        if words.contains(where: focusWords.contains) { return "systemAction" }
        if action != "systemAction", MacControlRequest.power(command, language: .english) != nil { return "systemAction" }
        return nil
    }

    /// "Stop the timer", "cancel my alarms"; not "remind me to turn off the oven timer".
    private static func stopsTimer(_ words: [String]) -> Bool {
        guard let first = words.first, stopWords.contains(first) else { return false }
        return words.contains { $0.hasPrefix("timer") || $0.hasPrefix("alarm") }
    }

    /// "Jot down …", "make a note …", "note that …".
    private static func takesNote(_ words: [String]) -> Bool {
        let phrases: [[String]] = [["jot", "down"], ["make", "a", "note"], ["take", "a", "note"], ["note", "that"], ["write", "down"]]
        return phrases.contains { phrase in words.count >= phrase.count && Array(words.prefix(phrase.count)) == phrase }
    }

    /// "Type …" / "write … here"; "what type of…" is a question, not dictation.
    private static func isDictation(_ words: [String]) -> Bool {
        words.first == "type" || (words.first == "write" && words.dropFirst().first == "here")
    }
}
