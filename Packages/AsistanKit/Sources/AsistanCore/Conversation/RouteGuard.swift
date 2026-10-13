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

    public static func review(action: String, command: String) -> String {
        let words = TurkishText.folded(command).split(separator: " ").map(String.init)
        switch action {
        case "searchWeb":
            let explicit = words.contains { searchVerbs.contains($0) || searchSites.contains(where: $0.hasPrefix) }
            return explicit ? action : "conversation"
        case "systemAction":
            if words.contains(where: { word in shortcutOnlyWords.contains(where: word.hasPrefix) }) { return "runShortcut" }
            let supported = words.contains { word in systemWords.contains(where: word.hasPrefix) }
            return supported ? action : "runShortcut"
        case "readCalendar":
            let opensApp = words.contains { openVerbs.contains($0) }
                && !words.contains { ["ne", "neler", "var", "mi", "kac"].contains($0) }
            return opensApp ? "openApp" : action
        default:
            return action
        }
    }
}
