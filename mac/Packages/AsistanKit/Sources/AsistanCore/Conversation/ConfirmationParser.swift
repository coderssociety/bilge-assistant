/// Interprets the user's spoken answer to "…yapayım mı?" / "Shall I…?". Errs toward `.unclear`: an
/// irreversible action must only run on a clear yes. Each language has its own words; mixing them would
/// let a folded Turkish word ("süre" → "sure") read as an English yes.
public enum ConfirmationParser {
    public enum Answer: Sendable, Equatable {
        case confirmed
        case rejected
        case unclear
    }

    private struct Words {
        let yes: Set<String>
        let no: Set<String>
        /// For sending messages: casual words ("tamam", "okay") from a TV or another person in the room
        /// must not be enough.
        let strictYes: Set<String>
        let noPhrases: [String]
    }

    private static let turkish = Words(
        yes: [
            "evet", "olur", "tamam", "onayliyorum", "onayla", "onay", "gonder", "yap", "tabii", "tabi", "aynen",
            "kesinlikle", "elbette", "peki", "devam", "sil", "ekle", "calistir",
        ],
        no: [
            "hayir", "iptal", "vazgec", "vazgectim", "yok", "istemiyorum", "dur", "durdur", "yapma", "gonderme",
            "silme", "ekleme", "calistirma", "bosver", "olmaz",
        ],
        strictYes: ["evet", "onayliyorum", "onayla", "gonder"],
        noPhrases: ["bos ver", "gerek yok"])

    private static let english = Words(
        yes: [
            "yes", "yeah", "yep", "yup", "sure", "ok", "okay", "confirm", "confirmed", "send", "ahead", "proceed",
            "absolutely", "definitely", "certainly", "delete", "add", "run",
        ],
        // Hesitation counts as no: "I'm not sure" or "wait" must never run the action.
        no: [
            "no", "nope", "nah", "cancel", "stop", "dont", "abort", "negative", "never", "not", "cant", "wont", "wait",
            "hold", "hang", "later", "maybe", "unsure",
        ],
        strictYes: ["yes", "confirm", "confirmed", "send"],
        noPhrases: ["never mind", "not now", "forget it", "do not"])

    public static func parse(_ text: String, strict: Bool = false, language: AssistantLanguage = .turkish) -> Answer {
        let table = language == .english ? english : turkish
        let folded = TurkishText.folded(text)
        let words = Set(folded.split(separator: " ").map(String.init))
        let saysNo = !words.isDisjoint(with: table.no) || table.noPhrases.contains { folded.contains($0) }
        let saysYes = !words.isDisjoint(with: strict ? table.strictYes : table.yes)
        switch (saysYes, saysNo) {
        case (true, false): return .confirmed
        case (false, true): return .rejected
        default: return .unclear
        }
    }
}
