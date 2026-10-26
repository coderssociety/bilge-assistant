import Foundation

/// The text of Excel, PowerPoint and OpenDocument files, read from the XML parts inside them. No system framework reads
/// these; the app takes the parts out of the zip and hands them here.
public enum OfficeDocumentText {
    public enum Kind: String, Sendable, CaseIterable {
        case xlsx, pptx, ods, odp
    }

    public enum ReadError: Error, Equatable {
        /// Office files never need a DTD; refusing one rules out entity expansion and external entities.
        case declaresEntities
        case malformed
    }

    /// The archive parts to read, in reading order: worksheets and slides by their number, not the archive's order.
    public static func parts(of kind: Kind, in names: [String]) -> [String] {
        switch kind {
        case .xlsx: numbered(names, in: "xl/worksheets/")
        case .pptx: numbered(names, in: "ppt/slides/")
        case .ods, .odp: names.contains("content.xml") ? ["content.xml"] : []
        }
    }

    public static let sharedStringsPart = "xl/sharedStrings.xml"

    /// The strings an xlsx file's text cells point into.
    public static func sharedStrings(_ xml: Data) throws -> [String] {
        let reader = try parse(xml, Collector(itemTag: "si", textTag: "t"))
        return reader.items
    }

    /// A worksheet's rows, cells separated by tabs; empty rows are left out.
    public static func sheet(_ xml: Data, shared: [String]) throws -> String {
        try parse(xml, SheetReader(shared: shared)).rows.filter { !$0.allSatisfy(\.isEmpty) }
            .map { $0.joined(separator: "\t") }.joined(separator: "\n")
    }

    /// A slide's paragraphs, one per line.
    public static func slide(_ xml: Data) throws -> String {
        try parse(xml, Collector(itemTag: "p", textTag: "t")).items.filter { !$0.isEmpty }.joined(separator: "\n")
    }

    /// An OpenDocument `content.xml`: paragraphs on their own lines, table cells separated by tabs.
    public static func openDocument(_ xml: Data) throws -> String {
        try parse(xml, OpenDocumentReader()).lines.filter { !$0.isEmpty }.joined(separator: "\n")
    }

    private static func numbered(_ names: [String], in folder: String) -> [String] {
        names.compactMap { name -> (Int, String)? in
            guard name.hasPrefix(folder), name.hasSuffix(".xml") else { return nil }
            let file = name.dropFirst(folder.count).dropLast(".xml".count)
            guard !file.contains("/"), let number = Int(file.drop(while: { !$0.isNumber })) else { return nil }
            return (number, name)
        }
        .sorted { $0.0 < $1.0 }
        .map(\.1)
    }

    private static func parse<Reader: XMLParserDelegate>(_ xml: Data, _ reader: Reader) throws -> Reader {
        let head = String(decoding: xml.prefix(4096), as: UTF8.self)
        guard !head.contains("<!DOCTYPE"), !head.contains("<!ENTITY") else { throw ReadError.declaresEntities }
        let parser = XMLParser(data: xml)
        parser.shouldResolveExternalEntities = false
        parser.shouldProcessNamespaces = true
        parser.delegate = reader
        guard parser.parse() else { throw ReadError.malformed }
        return reader
    }
}

/// The text of every `textTag` inside each `itemTag`, one string per item.
private final class Collector: NSObject, XMLParserDelegate {
    private let itemTag: String
    private let textTag: String
    private(set) var items: [String] = []
    private var current: String?
    private var inText = false

    init(itemTag: String, textTag: String) {
        self.itemTag = itemTag
        self.textTag = textTag
    }

    func parser(_ parser: XMLParser, didStartElement element: String, namespaceURI: String?, qualifiedName: String?,
                attributes: [String: String] = [:]) {
        if element == itemTag { current = "" }
        if element == textTag { inText = true }
    }

    func parser(_ parser: XMLParser, foundCharacters string: String) {
        if inText { current?.append(string) }
    }

    func parser(_ parser: XMLParser, didEndElement element: String, namespaceURI: String?, qualifiedName: String?) {
        if element == textTag { inText = false }
        if element == itemTag, let current {
            items.append(current)
            self.current = nil
        }
    }
}

private final class SheetReader: NSObject, XMLParserDelegate {
    private let shared: [String]
    private(set) var rows: [[String]] = []
    private var row: [String]?
    private var cellType: String?
    private var cell = ""
    private var isReading = false

    init(shared: [String]) {
        self.shared = shared
    }

    func parser(_ parser: XMLParser, didStartElement element: String, namespaceURI: String?, qualifiedName: String?,
                attributes: [String: String] = [:]) {
        switch element {
        case "row": row = []
        case "c":
            cellType = attributes["t"]
            cell = ""
        case "v", "t": isReading = true
        default: break
        }
    }

    func parser(_ parser: XMLParser, foundCharacters string: String) {
        if isReading { cell.append(string) }
    }

    func parser(_ parser: XMLParser, didEndElement element: String, namespaceURI: String?, qualifiedName: String?) {
        switch element {
        case "v", "t": isReading = false
        case "c":
            if cellType == "s", let index = Int(cell), shared.indices.contains(index) {
                row?.append(shared[index])
            } else {
                row?.append(cell)
            }
        case "row":
            if let row { rows.append(row) }
            row = nil
        default: break
        }
    }
}

private final class OpenDocumentReader: NSObject, XMLParserDelegate {
    /// Empty cells repeat to the sheet's edge (often over a thousand); past this many a row says nothing more.
    private static let maxRepeatedCells = 256

    private(set) var lines: [String] = []
    private var paragraph: String?
    private var cells: [String]?
    private var cellRepeat = 1
    private var depth = 0

    private static func number(_ attribute: String, in attributes: [String: String]) -> Int? {
        attributes.first { $0.key == attribute || $0.key.hasSuffix(":" + attribute) }.flatMap { Int($0.value) }
    }

    func parser(_ parser: XMLParser, didStartElement element: String, namespaceURI: String?, qualifiedName: String?,
                attributes: [String: String] = [:]) {
        switch element {
        case "table-row": cells = []
        case "table-cell", "covered-table-cell":
            cells?.append("")
            cellRepeat = min(max(Self.number("number-columns-repeated", in: attributes) ?? 1, 1), Self.maxRepeatedCells)
        case "p", "h":
            if paragraph == nil { paragraph = "" } else { depth += 1 }
        case "s": paragraph?.append(String(repeating: " ", count: Self.number("c", in: attributes) ?? 1))
        case "tab": paragraph?.append("\t")
        case "line-break": paragraph?.append("\n")
        default: break
        }
    }

    func parser(_ parser: XMLParser, foundCharacters string: String) {
        paragraph?.append(string)
    }

    func parser(_ parser: XMLParser, didEndElement element: String, namespaceURI: String?, qualifiedName: String?) {
        switch element {
        case "p", "h":
            if depth > 0 {
                depth -= 1
                return
            }
            guard let text = paragraph else { return }
            paragraph = nil
            if var row = cells, !row.isEmpty {
                row[row.count - 1] += row[row.count - 1].isEmpty ? text : "\n" + text
                cells = row
            } else {
                lines.append(text)
            }
        case "table-cell", "covered-table-cell":
            // A repeated cell stands for that many cells with the same content, so later columns keep their place.
            if let last = cells?.last, cellRepeat > 1 {
                cells?.append(contentsOf: repeatElement(last, count: cellRepeat - 1))
            }
            cellRepeat = 1
        case "table-row":
            if let row = cells {
                var trimmed = row
                while trimmed.last?.isEmpty == true { trimmed.removeLast() }
                lines.append(trimmed.joined(separator: "\t"))
            }
            cells = nil
        default: break
        }
    }
}
