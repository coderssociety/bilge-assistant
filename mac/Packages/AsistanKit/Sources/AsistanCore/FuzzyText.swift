public enum FuzzyText {
    /// 1 for identical strings, 0 for completely different ones (normalized Levenshtein).
    public static func similarity(_ lhs: String, _ rhs: String) -> Double {
        let longest = max(lhs.count, rhs.count)
        guard longest > 0 else { return 1 }
        return 1 - Double(levenshtein(Array(lhs), Array(rhs))) / Double(longest)
    }

    public static func levenshtein<Element: Equatable>(_ lhs: [Element], _ rhs: [Element]) -> Int {
        guard !lhs.isEmpty else { return rhs.count }
        guard !rhs.isEmpty else { return lhs.count }
        var previous = Array(0...rhs.count)
        for (i, left) in lhs.enumerated() {
            var current = [i + 1] + Array(repeating: 0, count: rhs.count)
            for (j, right) in rhs.enumerated() {
                current[j + 1] = min(previous[j] + (left == right ? 0 : 1), previous[j + 1] + 1, current[j] + 1)
            }
            previous = current
        }
        return previous[rhs.count]
    }
}
