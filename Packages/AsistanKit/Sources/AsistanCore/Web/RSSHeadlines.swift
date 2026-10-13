import Foundation

/// Item titles from an RSS 2.0 or Atom feed, in feed order.
public enum RSSHeadlines {
    public static func parse(_ data: Data, limit: Int) -> [String] {
        let delegate = Collector(limit: limit)
        let parser = XMLParser(data: data)
        parser.delegate = delegate
        parser.parse()
        return delegate.titles
    }

    private final class Collector: NSObject, XMLParserDelegate {
        let limit: Int
        var titles: [String] = []
        private var inItem = false
        private var current: String?

        init(limit: Int) {
            self.limit = limit
        }

        func parser(_ parser: XMLParser, didStartElement name: String, namespaceURI: String?, qualifiedName: String?,
                    attributes: [String: String] = [:]) {
            if name == "item" || name == "entry" { inItem = true }
            if inItem, name == "title" { current = "" }
        }

        func parser(_ parser: XMLParser, foundCharacters string: String) {
            current? += string
        }

        func parser(_ parser: XMLParser, foundCDATA block: Data) {
            current? += String(decoding: block, as: UTF8.self)
        }

        func parser(_ parser: XMLParser, didEndElement name: String, namespaceURI: String?, qualifiedName: String?) {
            if name == "title", let title = current {
                let cleaned = title.trimmingCharacters(in: .whitespacesAndNewlines)
                if !cleaned.isEmpty { titles.append(cleaned) }
                current = nil
                if titles.count >= limit { parser.abortParsing() }
            }
            if name == "item" || name == "entry" { inItem = false }
        }
    }
}
