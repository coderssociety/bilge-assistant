public enum TurkishNumberWords {
    private static let ones = ["", "bir", "iki", "üç", "dört", "beş", "altı", "yedi", "sekiz", "dokuz"]
    private static let tens = ["", "on", "yirmi", "otuz", "kırk", "elli", "altmış", "yetmiş", "seksen", "doksan"]
    private static let scales: [(value: Int, word: String)] = [
        (1_000_000_000_000, "trilyon"), (1_000_000_000, "milyar"), (1_000_000, "milyon"), (1000, "bin"),
    ]
    public static let monthNames = [
        "ocak", "şubat", "mart", "nisan", "mayıs", "haziran",
        "temmuz", "ağustos", "eylül", "ekim", "kasım", "aralık",
    ]

    public static func cardinal(_ value: Int) -> String {
        if value == 0 { return "sıfır" }
        if value < 0 { return "eksi " + cardinal(-value) }
        var words: [String] = []
        var rest = value
        for scale in scales where rest >= scale.value {
            let count = rest / scale.value
            rest %= scale.value
            // Turkish says "bin", not "bir bin"; larger scales keep "bir".
            if !(scale.word == "bin" && count == 1) { words.append(belowThousand(count)) }
            words.append(scale.word)
        }
        if rest > 0 { words.append(belowThousand(rest)) }
        return words.joined(separator: " ")
    }

    /// Reads a digit string such as minutes ("05") or decimals ("05") keeping leading zeros audible.
    public static func digitsPreservingLeadingZeros(_ digits: Substring) -> String {
        let zeros = digits.prefix(while: { $0 == "0" }).count
        let remainder = digits.dropFirst(zeros)
        var words = Array(repeating: "sıfır", count: remainder.isEmpty ? max(zeros, 1) : zeros)
        if let number = Int(remainder) { words.append(cardinal(number)) }
        return words.joined(separator: " ")
    }

    private static func belowThousand(_ value: Int) -> String {
        var words: [String] = []
        let hundreds = value / 100
        if hundreds > 0 { words.append(hundreds == 1 ? "yüz" : ones[hundreds] + " yüz") }
        let tensDigit = (value % 100) / 10
        if tensDigit > 0 { words.append(tens[tensDigit]) }
        let onesDigit = value % 10
        if onesDigit > 0 { words.append(ones[onesDigit]) }
        return words.joined(separator: " ")
    }
}
