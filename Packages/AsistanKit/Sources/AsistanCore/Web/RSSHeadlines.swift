import Foundation

/// Items from an RSS 2.0 or Atom feed, in feed order.
public enum RSSHeadlines {
    public struct Item: Equatable, Hashable, Sendable {
        public let title: String
        /// The article's address, when the feed gives one over http(s).
        public let link: URL?

        public init(title: String, link: URL?) {
            self.title = title
            self.link = link
        }
    }

    public static func parse(_ data: Data, limit: Int) -> [String] {
        items(data, limit: limit).map(\.title)
    }

    public static func items(_ data: Data, limit: Int) -> [Item] {
        let delegate = Collector(limit: limit)
        let parser = XMLParser(data: data)
        parser.delegate = delegate
        parser.parse()
        return delegate.items
    }

    private final class Collector: NSObject, XMLParserDelegate {
        let limit: Int
        var items: [Item] = []
        private var inItem = false
        private var title: String?
        private var link: String?
        private var field: String?
        private var current: String?

        init(limit: Int) {
            self.limit = limit
        }

        func parser(_ parser: XMLParser, didStartElement name: String, namespaceURI: String?, qualifiedName: String?,
                    attributes: [String: String] = [:]) {
            if name == "item" || name == "entry" {
                inItem = true
                (title, link) = (nil, nil)
            }
            guard inItem, name == "title" || name == "link" else { return }
            (field, current) = (name, "")
            // Atom gives the address as an attribute: <link rel="alternate" href="…"/>.
            if name == "link", let href = attributes["href"], (attributes["rel"] ?? "alternate") == "alternate" {
                link = href
            }
        }

        func parser(_ parser: XMLParser, foundCharacters string: String) {
            current? += string
        }

        func parser(_ parser: XMLParser, foundCDATA block: Data) {
            current? += String(decoding: block, as: UTF8.self)
        }

        func parser(_ parser: XMLParser, didEndElement name: String, namespaceURI: String?, qualifiedName: String?) {
            if name == field {
                if let text = current?.trimmingCharacters(in: .whitespacesAndNewlines), !text.isEmpty {
                    if name == "title" { title = text } else { link = text }
                }
                (field, current) = (nil, nil)
            }
            guard name == "item" || name == "entry" else { return }
            inItem = false
            if let title {
                let address = link.flatMap(URL.init(string:)).flatMap { ["http", "https"].contains($0.scheme ?? "") ? $0 : nil }
                items.append(Item(title: title, link: address))
            }
            if items.count >= limit { parser.abortParsing() }
        }
    }
}
