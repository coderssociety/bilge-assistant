/// Reads by how much to change the volume: "sesi yüzde 20 artır" → +20, "10 puan kıs" → -10.
/// Expects digitized text. A number with a case ending ("yüzde 20'ye") is a target level, not an amount.
public enum VolumeChange {
    private static let upStems = ["artir", "arttir", "yukselt"]
    private static let upWords: Set<String> = ["ac", "acar", "acsana"]
    private static let downStems = ["azalt", "dusur", "alcalt"]
    private static let downWords: Set<String> = ["kis", "kisar", "kissana"]

    public static func parse(_ text: String) -> Int? {
        let words = text.split(whereSeparator: \.isWhitespace).map { TurkishText.folded(String($0)) }
        guard words.contains(where: { $0.hasPrefix("ses") }),
              let amount = words.compactMap({ Int($0) }).first, (1...100).contains(amount) else { return nil }
        if words.contains(where: { word in upWords.contains(word) || upStems.contains(where: word.hasPrefix) }) { return amount }
        if words.contains(where: { word in downWords.contains(word) || downStems.contains(where: word.hasPrefix) }) { return -amount }
        return nil
    }
}
