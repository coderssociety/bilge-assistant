/// Phone numbers as Messages expects them: digits only, with a country code.
public enum PhoneNumber {
    /// "0532 123 45 67" → "+905321234567"; "+90 (532) 123-45-67" → "+905321234567"; "532 123 4567" → "+905321234567".
    /// Returns nil when the text is not a plausible phone number.
    public static func normalized(_ text: String, defaultCountryCode: String = "90") -> String? {
        let hasPlus = text.trimmingCharacters(in: .whitespaces).hasPrefix("+")
        let digits = text.filter(\.isNumber)
        guard digits.count >= 7, digits.count <= 15, text.allSatisfy({ $0.isNumber || " +-().".contains($0) }) else { return nil }
        if hasPlus { return "+" + digits }
        if digits.hasPrefix("00") { return "+" + digits.dropFirst(2) }
        if digits.hasPrefix("0") { return "+" + defaultCountryCode + digits.dropFirst() }
        if digits.count == 10 { return "+" + defaultCountryCode + digits }
        return "+" + digits
    }
}
