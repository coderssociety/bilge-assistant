/// English counterpart of `RouteGuard.review`: corrects routing confusions the model keeps making with
/// English requests (Focus read as "lock screen", knowledge questions sent to web search, typing or
/// other-day reminders set as timers).
public enum EnglishRouteGuard {
    private static let searchWords: Set<String> = [
        "search", "google", "look", "find", "youtube", "wikipedia", "web", "internet", "online", "maps", "browse",
    ]
    private static let systemWords = ["lock", "sleep", "dark", "light", "appearance", "theme", "screensaver"]
    private static let shortcutOnlyWords = ["focus", "disturb", "bright"]
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
    private static let playbackWords: Set<String> = ["next", "previous", "skip", "pause", "resume"]
    private static let selectionWords: Set<String> = ["selected", "highlighted", "selection"]
    private static let stopWords: Set<String> = ["stop", "cancel", "delete", "clear", "remove", "turn"]

    public static func review(action: String, command: String, previousAction: String? = nil) -> String {
        let words = TurkishText.folded(command).split(separator: " ").map(String.init)
        // "Type see you tomorrow" was read as a timer because of "tomorrow".
        if isDictation(words), action != "createNote" { return "typeText" }
        // Only answers about the selection; copying or sending it keeps its own action.
        if words.contains(where: selectionWords.contains), ["conversation", "readScreen", "searchWeb"].contains(action) {
            return "readSelection"
        }
        if stopsTimer(words), action != "manageTimers" { return "manageTimers" }
        if takesNote(words), action != "createNote" { return "createNote" }
        switch action {
        case "quitApp" where words.contains { $0.hasPrefix("window") }:
            return "windowControl"
        case "setTimer":
            // Timers live in the app and fire only today.
            let reminds = words.contains { $0.hasPrefix("remind") }
            let otherDay = words.contains(where: otherDayWords.contains)
            let hasTime = words.contains { word in word.contains(where: \.isNumber) || timeWords.contains(where: word.hasPrefix) }
            return reminds && (otherDay || !hasTime) ? "addReminder" : action
        case "searchWeb":
            return words.contains(where: searchWords.contains) ? action : "conversation"
        case "systemAction":
            if words.contains(where: { word in shortcutOnlyWords.contains(where: word.hasPrefix) }) { return "runShortcut" }
            let supported = words.contains { word in systemWords.contains(where: word.hasPrefix) }
            return supported ? action : "runShortcut"
        case "weather":
            let aboutWeather = words.contains { word in weatherWords.contains(where: word.hasPrefix) }
            return aboutWeather || previousAction == action ? action : "conversation"
        case "openApp":
            let searches = words.contains { $0 == "search" || $0 == "find" } && words.contains(where: searchWords.contains)
            return searches ? "searchWeb" : action
        case "readCalendar":
            let opensApp = words.first.map(openVerbs.contains) == true && !words.contains(where: questionWords.contains)
            return opensApp ? "openApp" : action
        case "readClipboard":
            return words.first == "copy" ? "copyToClipboard" : action
        case "playMusic":
            return words.contains(where: playbackWords.contains) ? "controlMusic" : action
        case "conversation":
            let isArithmetic = words.contains { $0.contains(where: \.isNumber) } && words.contains(where: mathWords.contains)
            return isArithmetic ? "calculate" : action
        default:
            return action
        }
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
