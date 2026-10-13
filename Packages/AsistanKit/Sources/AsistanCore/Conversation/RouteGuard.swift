/// Deterministic checks on the model's routing decision for confusions it keeps making even with
/// explicit instructions: answering questions by opening a web search, treating Focus modes as
/// "lock screen", and reading the calendar when the user asked to open the Calendar app.
public enum RouteGuard {
    private static let searchVerbs: Set<String> = [
        "ara", "arar", "arat", "aratir", "arayin", "arasana", "bul", "bulur", "goster", "gosterir", "search",
    ]
    private static let searchSites = ["google", "youtube", "harita", "vikipedi", "wikipedia", "internet"]
    private static let systemWords = ["kilit", "uyu", "uyku", "karanlik", "aydinlik", "koyu", "gorunum", "tema"]
    private static let shortcutOnlyWords = ["odak", "odag", "rahatsiz", "parlak"]
    private static let openVerbs: Set<String> = ["ac", "acar", "acsana", "baslat"]
    private static let weatherWords = [
        "hava", "derece", "sicak", "soguk", "yagmur", "yagis", "kar", "ruzgar", "gunes", "bulut", "nem", "firtina",
        "semsiye", "mont", "ceket", "dolu", "sis", "don",
    ]

    private static let acknowledgementWords: Set<String> = [
        "evet", "hayir", "tamam", "olur", "peki", "tesekkurler", "tesekkur", "ederim", "sag", "ol", "sagol", "cok",
        "eyvallah", "super", "harika", "guzel", "iyi", "anladim", "tamamdir",
        "gunaydin", "merhaba", "selam", "aksamlar", "geceler", "gunler", "hosca", "kal", "nasilsin",
    ]

    /// Answers that need no model at all. A bare "Evet" in the follow-up window once made the model
    /// repeat the previous action with invented arguments, and "Günaydın" was once read as a time question.
    public static func preRoute(_ command: String) -> String? {
        let words = TurkishText.folded(command).split(separator: " ").map(String.init)
        guard !words.isEmpty, words.count <= 3, words.allSatisfy(acknowledgementWords.contains) else { return nil }
        return "conversation"
    }

    public static func review(action: String, command: String) -> String {
        let words = TurkishText.folded(command).split(separator: " ").map(String.init)
        // "şunu yaz yarın sabah görüşelim" was read as an alarm because of its time words.
        if isDictation(words), action != "createNote" { return "typeText" }
        switch action {
        case "searchWeb":
            let explicit = words.contains { searchVerbs.contains($0) || searchSites.contains(where: $0.hasPrefix) }
            return explicit ? action : "conversation"
        case "systemAction":
            if words.contains(where: { word in shortcutOnlyWords.contains(where: word.hasPrefix) }) { return "runShortcut" }
            let supported = words.contains { word in systemWords.contains(where: word.hasPrefix) }
            return supported ? action : "runShortcut"
        case "weather":
            // "Bana bir tavsiye ver" was once answered with a weather report.
            let aboutWeather = words.contains { word in weatherWords.contains(where: word.hasPrefix) }
            return aboutWeather ? action : "conversation"
        case "openApp":
            // "Haritalarda Kadıköy'ü göster" opened Maps without the place.
            let searches = words.contains { searchVerbs.contains($0) && !openVerbs.contains($0) }
                && words.contains { word in searchSites.contains(where: word.hasPrefix) }
            return searches ? "searchWeb" : action
        case "readCalendar":
            let opensApp = words.contains { openVerbs.contains($0) }
                && !words.contains { ["ne", "neler", "var", "mi", "kac"].contains($0) }
            return opensApp ? "openApp" : action
        default:
            return action
        }
    }

    /// "Yaz" is also "summer" ("yaz şarkıları"), so it only counts with "şunu"/"buraya" or as the last word.
    private static func isDictation(_ words: [String]) -> Bool {
        guard words.contains("yaz") else { return false }
        return words.last == "yaz" || words.contains("sunu") || words.contains("buraya")
    }
}
