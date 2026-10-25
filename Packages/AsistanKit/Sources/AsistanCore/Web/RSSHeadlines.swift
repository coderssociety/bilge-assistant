import Foundation

/// Items from an RSS 2.0 or Atom feed, in feed order.
public enum RSSHeadlines {
    public struct Item: Equatable, Hashable, Sendable {
        public let title: String
        /// The article's address, when the feed gives one over http(s).
        public let link: URL?
        /// The attached audio (a podcast episode), when given over http(s).
        public let enclosure: URL?
        public let published: Date?

        public init(title: String, link: URL?, enclosure: URL? = nil, published: Date? = nil) {
            self.title = title
            self.link = link
            self.enclosure = enclosure
            self.published = published
        }
    }

    private static let dateFormats = ["EEE, d MMM yyyy HH:mm:ss Z", "EEE, d MMM yyyy HH:mm:ss zzz", "d MMM yyyy HH:mm:ss Z",
                                      "EEE, d MMM yyyy HH:mm Z", "EEE, d MMM yyyy HH:mm:ss"]

    /// RFC 822 as RSS uses it, or ISO 8601 as Atom does.
    static func date(_ text: String) -> Date? {
        let text = text.trimmingCharacters(in: .whitespacesAndNewlines)
        if let iso = try? Date.ISO8601FormatStyle().parse(text) { return iso }
        if let iso = try? Date.ISO8601FormatStyle(includingFractionalSeconds: true).parse(text) { return iso }
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = TimeZone(identifier: "GMT")
        for format in dateFormats {
            formatter.dateFormat = format
            if let date = formatter.date(from: text) { return date }
        }
        return nil
    }

    private static func webAddress(_ text: String?) -> URL? {
        text.flatMap { URL(string: $0.trimmingCharacters(in: .whitespacesAndNewlines)) }
            .flatMap { ["http", "https"].contains($0.scheme?.lowercased() ?? "") ? $0 : nil }
    }

    /// Images and PDFs ride along as enclosures too; a missing type is taken as audio.
    private static func isAudio(type: String?) -> Bool {
        guard let type = type?.lowercased(), !type.isEmpty else { return true }
        return type.hasPrefix("audio/") || type == "video/mp4" || type == "video/x-m4v"
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
        private var enclosure: String?
        private var published: String?
        private var field: String?
        private var current: String?

        init(limit: Int) {
            self.limit = limit
        }

        func parser(_ parser: XMLParser, didStartElement name: String, namespaceURI: String?, qualifiedName: String?,
                    attributes: [String: String] = [:]) {
            if name == "item" || name == "entry" {
                inItem = true
                (title, link, enclosure, published) = (nil, nil, nil, nil)
            }
            guard inItem else { return }
            if name == "enclosure", enclosure == nil, let url = attributes["url"], RSSHeadlines.isAudio(type: attributes["type"]) {
                enclosure = url
            }
            guard ["title", "link", "pubDate", "published"].contains(name) else { return }
            (field, current) = (name, "")
            // Atom gives the address as an attribute: <link rel="alternate" href="…"/>, and audio as rel="enclosure".
            if name == "link", let href = attributes["href"] {
                switch attributes["rel"] ?? "alternate" {
                case "alternate": link = href
                case "enclosure" where enclosure == nil && RSSHeadlines.isAudio(type: attributes["type"]): enclosure = href
                default: break
                }
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
                    switch name {
                    case "title": title = text
                    case "link": link = text
                    default: published = text
                    }
                }
                (field, current) = (nil, nil)
            }
            guard name == "item" || name == "entry" else { return }
            inItem = false
            if let title {
                items.append(Item(title: title, link: RSSHeadlines.webAddress(link), enclosure: RSSHeadlines.webAddress(enclosure),
                                  published: published.flatMap(RSSHeadlines.date)))
            }
            if items.count >= limit { parser.abortParsing() }
        }
    }
}
