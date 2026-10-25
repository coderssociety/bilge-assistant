import Foundation

/// Prices as the Turkish sources write them ("6.384,76", "$3.995,89", "10.285", or a JSON number) and as
/// they are spoken.
public enum PriceNumber {
    public static func parse(_ value: Any?) -> Double? {
        if let number = value as? NSNumber { return number.doubleValue }
        guard let text = value as? String else { return nil }
        let digits = String(text.filter { $0.isNumber || $0 == "." || $0 == "," })
        guard !digits.isEmpty else { return nil }
        if digits.contains(",") {
            return Double(digits.replacingOccurrences(of: ".", with: "").replacingOccurrences(of: ",", with: "."))
        }
        return Double(digits.wholeMatch(of: /\d{1,3}(\.\d{3})+/) != nil ? digits.replacingOccurrences(of: ".", with: "") : digits)
    }

    /// Whole units above a thousand ("6.385"), kuruş below ("77,50").
    public static func spoken(_ value: Double, language: AssistantLanguage) -> String {
        let decimals = value >= 1000 ? 0...0 : 2...2
        return value.formatted(.number.precision(.fractionLength(decimals)).locale(language.locale))
    }
}
