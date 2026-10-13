import Foundation

/// Readable text from a web page, without markup, scripts or styles. Not a full HTML parser:
/// good enough to summarize an article.
public enum HTMLText {
    private static let droppedBlocks = ["script", "style", "noscript", "svg", "head", "nav", "footer", "form"]
    private static let blockTags = ["p", "div", "br", "li", "h1", "h2", "h3", "h4", "tr", "section", "article"]
    private static let entities: [String: String] = [
        "&nbsp;": " ", "&amp;": "&", "&lt;": "<", "&gt;": ">", "&quot;": "\"", "&#39;": "'", "&apos;": "'",
        "&rsquo;": "’", "&lsquo;": "‘", "&ldquo;": "“", "&rdquo;": "”", "&hellip;": "…", "&ndash;": "–", "&mdash;": "—",
    ]

    /// Pages are cut to this size first; extraction is meant for article text, not whole sites.
    private static let maxInputCharacters = 600_000

    public static func extract(_ html: String) -> String {
        var text = String(html.prefix(maxInputCharacters))
        for tag in droppedBlocks { text = removingBlocks(tag, from: text) }
        text = text.replacingOccurrences(of: "<!--[\\s\\S]*?-->", with: " ", options: .regularExpression)
        for tag in blockTags {
            text = text.replacingOccurrences(of: "</?\(tag)\\b[^>]*>", with: "\n", options: [.regularExpression, .caseInsensitive])
        }
        text = text.replacingOccurrences(of: "<[^>]+>", with: " ", options: .regularExpression)
        for (entity, value) in entities { text = text.replacingOccurrences(of: entity, with: value) }
        text = decodeNumericEntities(text)
        let lines = text.split(separator: "\n").map {
            $0.split(whereSeparator: \.isWhitespace).joined(separator: " ")
        }
        return lines.filter { !$0.isEmpty }.joined(separator: "\n")
    }

    /// One forward scan per tag. A lazy regex rescans to the end for every unclosed tag, which is
    /// quadratic on pages with thousands of them.
    private static func removingBlocks(_ tag: String, from text: String) -> String {
        var result = ""
        var position = text.startIndex
        while let open = text.range(of: "<\(tag)", options: .caseInsensitive, range: position..<text.endIndex) {
            let next = open.upperBound < text.endIndex ? text[open.upperBound] : " "
            guard !next.isLetter, !next.isNumber else {
                result += text[position..<open.upperBound]
                position = open.upperBound
                continue
            }
            result += text[position..<open.lowerBound] + " "
            guard let close = text.range(of: "</\(tag)>", options: .caseInsensitive, range: open.upperBound..<text.endIndex) else {
                return result
            }
            position = close.upperBound
        }
        return result + text[position...]
    }

    public static func title(_ html: String) -> String? {
        guard let range = html.range(of: "<title[^>]*>([\\s\\S]*?)</title>", options: [.regularExpression, .caseInsensitive])
        else { return nil }
        let title = extract(String(html[range])).trimmingCharacters(in: .whitespacesAndNewlines)
        return title.isEmpty ? nil : title
    }

    private static func decodeNumericEntities(_ text: String) -> String {
        guard let pattern = try? NSRegularExpression(pattern: "&#(x?)([0-9a-fA-F]+);") else { return text }
        var result = text
        for match in pattern.matches(in: text, range: NSRange(text.startIndex..., in: text)).reversed() {
            guard let whole = Range(match.range, in: text), let digits = Range(match.range(at: 2), in: text) else { continue }
            let isHex = match.range(at: 1).length > 0
            guard let value = UInt32(text[digits], radix: isHex ? 16 : 10), let scalar = Unicode.Scalar(value) else { continue }
            result.replaceSubrange(whole, with: String(Character(scalar)))
        }
        return result
    }
}
