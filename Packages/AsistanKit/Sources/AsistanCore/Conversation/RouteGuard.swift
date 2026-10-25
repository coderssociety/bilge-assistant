/// Deterministic checks on the model's routing decision for confusions it keeps making even with
/// explicit instructions: answering questions by opening a web search, sending Focus, brightness or
/// Bluetooth to a shortcut or "lock screen", and reading the calendar when the user asked to open the
/// Calendar app.
public enum RouteGuard {
    private static let searchVerbs: Set<String> = [
        "ara", "arar", "arat", "aratir", "arayin", "arasana", "bul", "bulur", "goster", "gosterir", "search",
    ]
    private static let searchSites = ["google", "youtube", "harita", "vikipedi", "wikipedia", "internet"]
    private static let systemWords = ["kilit", "uyu", "uyku", "karanlik", "aydinlik", "koyu", "gorunum", "tema", "karart"]
    private static let focusWords = ["odak", "odag", "rahatsiz"]
    private static let openVerbs: Set<String> = ["ac", "acar", "acsana", "baslat"]
    private static let weatherWords = [
        "hava", "derece", "sicak", "soguk", "yagmur", "yagis", "kar", "ruzgar", "gunes", "bulut", "nem", "firtina",
        "semsiye", "mont", "ceket", "dolu", "sis", "don",
    ]

    private static let readWords: Set<String> = ["oku", "okur", "okusana", "okuyabilir", "okuyun", "yaziyor", "yaziyormus"]
    private static let readStems = ["ozetle", "ozetin", "icerig", "anlatiyor", "bahsediyor"]

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
        // "Alışveriş notuma süt ekle" is not a reminder, and "…notuma süt yaz" is not dictation.
        if NoteRequest.addition(in: command) != nil { return "appendToNote" }
        if NoteRequest.asksForList(command) { return "readNotes" }
        // "Annemi ara" is a phone call, not a web search; "Atatürk'ü internette ara" stays a search.
        if CallRequest.parse(command) != nil { return "callContact" }
        if action == "callContact", words.contains(where: { word in searchSites.contains(where: word.hasPrefix) }) {
            return "searchWeb"
        }
        // "Buna yanıt ver: …" after reading mail answers that mail; "…diye cevap yaz" is not dictation.
        if MailReplyRequest.parse(command) != nil, previousAction == "readMail" || MailReplyRequest.mentionsMail(command) {
            return "replyMail"
        }
        // "Yarınki toplantıyı iptal et" was taken for reading the calendar or adding to it.
        if let calendarAction = CalendarChange.reviewedAction(action, command: command, language: .turkish) { return calendarAction }
        // "şunu yaz yarın sabah görüşelim" was read as an alarm because of its time words.
        if isDictation(words), action != "createNote" { return "typeText" }
        // "geri al" (undo) outside a spreadsheet was once routed to quitApp.
        if action == "quitApp", words.contains("geri"), words.contains(where: { $0.hasPrefix("al") }) { return "conversation" }
        // Closing a window must not quit the whole app.
        if action == "quitApp", words.contains(where: { $0.hasPrefix("pencere") }) { return "windowControl" }
        if let control = macControl(action: action, words: words, command: command) { return control }
        switch action {
        case "setTimer":
            // Timers live in the app and fire only today; "yarın sabah süt almayı hatırlat" was set as one.
            let reminds = words.contains { $0.hasPrefix("hatirlat") || $0 == "unutma" }
            let otherDay = words.contains { word in otherDayWords.contains(where: word.hasPrefix) }
            let hasTime = words.contains { word in word.contains(where: \.isNumber) || durationWords.contains(where: word.hasPrefix) }
            return reminds && (otherDay || !hasTime) ? "addReminder" : action
        case "searchWeb":
            let explicit = words.contains { searchVerbs.contains($0) || searchSites.contains(where: $0.hasPrefix) }
            return explicit ? action : "conversation"
        case "systemAction":
            // "Ekranı karart/kapat" turns the display off; it went to runShortcut, which had no such shortcut.
            let turnsScreenOff = words.contains { $0.hasPrefix("ekran") } && words.contains { $0.hasPrefix("kapat") }
            let supported = turnsScreenOff || words.contains { word in systemWords.contains(where: word.hasPrefix) }
                || MacControlRequest.power(command, language: .turkish) != nil
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
        case "files":
            // "Son indirdiğim PDF'i özetle" opened the newest download instead of reading it.
            let reads = words.contains { word in readWords.contains(word) || readStems.contains(where: word.hasPrefix) }
            return reads ? "readDocument" : action
        case "readCalendar":
            let opensApp = words.contains { openVerbs.contains($0) }
                && !words.contains { ["ne", "neler", "var", "mi", "kac"].contains($0) }
            return opensApp ? "openApp" : action
        case "exchangeRate":
            // Gold is priced by its own tool; the rates source knows only currencies.
            return words.contains { $0.hasPrefix("altin") || $0 == "ons" } ? "goldPrice" : action
        case "conversation":
            // Clear encyclopedic questions ("fotosentez nedir") are answered from Wikipedia rather than from memory.
            return EncyclopediaQuestion.subject(in: command, language: .turkish) != nil ? "wikipedia" : action
        default:
            return action
        }
    }

    /// Focus, brightness, Bluetooth and power have their own actions now; the model still sends them to
    /// runShortcut, systemAction, setWiFi or quitApp ("Mac'i kapat"). A named shortcut stays a shortcut.
    private static func macControl(action: String, words: [String], command: String) -> String? {
        guard ["runShortcut", "systemAction", "setWiFi", "quitApp", "openApp"].contains(action),
              !words.contains(where: { $0.hasPrefix("kestirme") || $0.hasPrefix("ayar") }) else { return nil }
        if words.contains(where: { $0.hasPrefix("parlak") }) { return "setBrightness" }
        if words.contains(where: { $0.hasPrefix("bluetooth") }) { return "setBluetooth" }
        if words.contains(where: { word in focusWords.contains(where: word.hasPrefix) }) { return "systemAction" }
        if action != "systemAction", MacControlRequest.power(command, language: .turkish) != nil { return "systemAction" }
        return nil
    }

    /// "Yaz" is also "summer" ("yaz şarkıları"), so it only counts with "şunu"/"buraya" or as the last word.
    private static func isDictation(_ words: [String]) -> Bool {
        guard words.contains("yaz") else { return false }
        return words.last == "yaz" || words.contains("sunu") || words.contains("buraya")
    }
}
