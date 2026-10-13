/// Splits "Safari'yi aç ve sesi yüzde 30 yap" into separate commands. Plain "ve" only splits after
/// a known imperative, so "kahve ve süt almayı hatırlat" or "Ali ve Veli'ye yaz" stay whole.
public enum CompoundCommand {
    private static let sequenceMarkers: [[String]] = [["ve", "sonra"], ["sonra", "da"], ["daha", "sonra"], ["ardindan"], ["ayrica"], ["bir", "de"]]
    private static let imperatives: Set<String> = [
        "ac", "kapat", "yap", "ekle", "gonder", "at", "yaz", "oku", "cal", "kur", "bul", "soyle", "al", "ara", "goster",
        "durdur", "kilitle", "gizle", "olustur", "hatirlat", "sil", "kopyala", "ozetle", "cevir", "tamamla", "isaretle",
        "baslat", "degistir", "ayarla", "artir", "azalt", "kis", "getir", "git", "bak", "anlat", "kucult", "tasi", "kaydet",
        "cek", "gec", "yolla", "sor", "hesapla", "listele", "kontrol", "et",
    ]
    private static let minimumPartWords = 2

    public static func split(_ text: String) -> [String]? {
        let tokens = text.split(whereSeparator: \.isWhitespace).map(String.init)
        let folded = tokens.map { TurkishText.folded($0) }
        var parts: [[String]] = []
        var current: [String] = []
        var index = 0
        while index < tokens.count {
            if let marker = marker(at: index, in: folded, after: current) {
                parts.append(current)
                current = []
                index += marker
                continue
            }
            current.append(tokens[index])
            index += 1
        }
        parts.append(current)
        let commands = parts.map { $0.joined(separator: " ").trimmingCharacters(in: .punctuationCharacters.union(.whitespaces)) }
        guard commands.count >= 2, commands.allSatisfy({ $0.split(separator: " ").count >= minimumPartWords }) else { return nil }
        return commands
    }

    private static let references: Set<String> = [
        "ona", "onu", "onun", "ondan", "onlara", "onlari", "bunu", "buna", "bunun", "bundan", "sunu", "oraya", "orada",
        "ozeti", "ozetini", "ozetle", "sonucu", "sonucunu", "aynisini", "bulduğun", "buldugun", "bulduklarini", "icerigini",
        "numarasina", "adresine", "metni", "metnini",
    ]

    /// True when a later part refers to an earlier one's result ("Ahmet'in numarasını bul ve ona mesaj at",
    /// "PDF'i özetle ve özeti panoya kopyala"); such requests need planning, the others can run one by one.
    public static func hasDependentParts(_ parts: [String]) -> Bool {
        parts.dropFirst().contains { part in
            TurkishText.folded(part).split(separator: " ").contains { references.contains(String($0)) }
        }
    }

    /// Length of the separator starting at `index`, or nil when there is none there.
    private static func marker(at index: Int, in folded: [String], after current: [String]) -> Int? {
        guard !current.isEmpty else { return nil }
        for marker in sequenceMarkers where Array(folded[index..<min(index + marker.count, folded.count)]) == marker {
            return marker.count
        }
        let previous = TurkishText.folded(current.last ?? "").trimmingCharacters(in: .punctuationCharacters)
        if folded[index] == "ve", imperatives.contains(previous) { return 1 }
        return nil
    }
}
