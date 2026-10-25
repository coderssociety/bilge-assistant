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

    private static let otherDayWords: Set<String> = [
        "yarin", "obur", "pazartesi", "sali", "carsamba", "persembe", "cuma", "cumartesi", "pazar", "haftaya", "hafta",
    ]
    private static let durationWords = ["saniye", "dakika", "saat", "sabah", "aksam", "ogle", "gece"]

    private static let acknowledgementWords: Set<String> = [
        "evet", "hayir", "tamam", "olur", "peki", "tesekkurler", "tesekkur", "ederim", "sag", "ol", "sagol", "cok",
        "eyvallah", "super", "harika", "guzel", "iyi", "anladim", "tamamdir",
        "gunaydin", "merhaba", "selam", "aksamlar", "geceler", "gunler", "hosca", "kal", "nasilsin",
    ]

    private static let englishAcknowledgementWords: Set<String> = [
        "yes", "yeah", "no", "ok", "okay", "alright", "sure", "thanks", "thank", "you", "very", "much", "great",
        "cool", "nice", "awesome", "perfect", "got", "it", "good", "morning", "evening", "night", "hello", "hi", "hey",
        "bye", "goodbye", "see", "later",
    ]

    /// Answers that need no model at all. A bare "Evet" in the follow-up window once made the model
    /// repeat the previous action with invented arguments, and "Günaydın" was once read as a time question.
    public static func preRoute(_ command: String, language: AssistantLanguage = .turkish) -> String? {
        let words = TurkishText.folded(command).split(separator: " ").map(String.init)
        let acknowledgements = language == .english ? englishAcknowledgementWords : acknowledgementWords
        guard !words.isEmpty, words.count <= 3, words.allSatisfy(acknowledgements.contains) else { return nil }
        return "conversation"
    }

    /// `previousAction` is the tool of the turn just before, for follow-ups like "peki yarın?" after a weather answer.
    public static func review(action: String, command: String, previousAction: String? = nil) -> String {
        let words = TurkishText.folded(command).split(separator: " ").map(String.init)
        // "şunu yaz yarın sabah görüşelim" was read as an alarm because of its time words.
        if isDictation(words), action != "createNote" { return "typeText" }
        // "geri al" (undo) outside a spreadsheet was once routed to quitApp.
        if action == "quitApp", words.contains("geri"), words.contains(where: { $0.hasPrefix("al") }) { return "conversation" }
        switch action {
        case "setTimer":
            // Timers live in the app and fire only today; "yarın sabah süt almayı hatırlat" was set as one.
            let reminds = words.contains { $0.hasPrefix("hatirlat") }
            let otherDay = words.contains { word in otherDayWords.contains(where: word.hasPrefix) }
            let hasTime = words.contains { word in word.contains(where: \.isNumber) || durationWords.contains(where: word.hasPrefix) }
            return reminds && (otherDay || !hasTime) ? "addReminder" : action
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
            return aboutWeather || previousAction == action ? action : "conversation"
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
