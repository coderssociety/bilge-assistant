/// Interprets the user's spoken answer to "…yapayım mı?". Errs toward `.unclear`: an irreversible
/// action must only run on a clear yes.
public enum ConfirmationParser {
    public enum Answer: Sendable, Equatable {
        case confirmed
        case rejected
        case unclear
    }

    private static let yesWords: Set<String> = [
        "evet", "olur", "tamam", "onayliyorum", "onayla", "onay", "gonder", "yap", "tabii", "tabi", "aynen",
        "kesinlikle", "elbette", "peki", "devam", "sil", "ekle", "calistir",
    ]
    private static let noWords: Set<String> = [
        "hayir", "iptal", "vazgec", "vazgectim", "yok", "istemiyorum", "dur", "durdur", "yapma", "gonderme",
        "silme", "ekleme", "calistirma", "bosver", "olmaz",
    ]
    /// For sending messages: casual words ("tamam", "peki", "yap") from a TV or another person in the
    /// room must not be enough.
    private static let strictYesWords: Set<String> = ["evet", "onayliyorum", "onayla", "gonder"]
    private static let noPhrases = ["bos ver", "gerek yok"]

    public static func parse(_ text: String, strict: Bool = false) -> Answer {
        let folded = TurkishText.folded(text)
        let words = Set(folded.split(separator: " ").map(String.init))
        let saysNo = !words.isDisjoint(with: noWords) || noPhrases.contains { folded.contains($0) }
        let saysYes = !words.isDisjoint(with: strict ? strictYesWords : yesWords)
        switch (saysYes, saysNo) {
        case (true, false): return .confirmed
        case (false, true): return .rejected
        default: return .unclear
        }
    }
}
