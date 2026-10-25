import Foundation

/// Whether a request about e-mail wants the messages themselves or only how many there are and from whom:
/// "maillerimi oku" and "içeriğini oku" read them, "kaç mailim var" counts them.
public enum MailRequest {
    private static let contentWords = ["oku", "icerig", "icerik", "yaziyor", "yazmis", "yazdi", "yazilmis", "detay",
                                       "ayrinti", "ozet", "anlat", "metin", "metni", "read", "content", "says", "say",
                                       "summar", "body", "detail"]

    public static func asksForContent(_ command: String) -> Bool {
        TurkishText.folded(command).split { !$0.isLetter }.contains { word in
            contentWords.contains { word.hasPrefix($0) }
        }
    }
}
