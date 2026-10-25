/// A spoken file search, "dün indirdiğim Excel dosyası" or "geçen haftaki bütçe sunumu": name words in any
/// order, the kind of file and when it was changed, turned into a Spotlight query.
public struct FileQuery: Equatable, Sendable {
    public enum Kind: CaseIterable, Sendable {
        case pdf, wordProcessing, spreadsheet, presentation, image, plainText

        public var extensions: Set<String> {
            switch self {
            case .pdf: ["pdf"]
            case .wordProcessing: ["doc", "docx", "odt", "pages"]
            case .spreadsheet: ["xlsx", "xls", "numbers", "csv"]
            case .presentation: ["key", "ppt", "pptx"]
            case .image: ["jpg", "jpeg", "png", "heic", "gif", "tiff", "webp"]
            case .plainText: ["txt", "md", "rtf"]
            }
        }

        /// Beginnings of the folded words that name it; Turkish adds endings ("PDF'i", "sunumu", "resmi").
        fileprivate var stems: [String] {
            switch self {
            case .pdf: ["pdf"]
            case .wordProcessing: ["word", "docx", "pages"]
            case .spreadsheet: ["excel", "tablo", "xlsx", "numbers", "csv", "spreadsheet"]
            case .presentation: ["sunum", "powerpoint", "keynote", "slayt", "slide", "presentation", "pptx"]
            case .image: ["resim", "resm", "foto", "gorsel", "image", "photo", "picture", "png", "jpg", "jpeg"]
            case .plainText: ["metin", "metn", "txt", "text"]
            }
        }
    }

    public enum Period: Equatable, Sendable {
        case today, yesterday, thisWeek, lastWeek, thisMonth, lastMonth
    }

    /// Letters and digits only, in the order said; matched as parts of the file name, ignoring case. Not
    /// lowercased here: Turkish rules would make "Invoice" "ınvoice", which no longer matches.
    public let nameWords: [String]
    public let kinds: Set<Kind>
    public let period: Period?

    public init(nameWords: [String] = [], kinds: Set<Kind> = [], period: Period? = nil) {
        self.nameWords = nameWords
        self.kinds = kinds
        self.period = period
    }

    public var isEmpty: Bool { nameWords.isEmpty && kinds.isEmpty && period == nil }

    /// Extensions of the kinds asked for; empty when no kind was named.
    public var extensions: Set<String> {
        kinds.reduce(into: Set<String>()) { $0.formUnion($1.extensions) }
    }

    /// The same search with the kind and time of `other` added, for a model-extracted query that left them out.
    public func addingFilters(of other: FileQuery) -> FileQuery {
        FileQuery(nameWords: nameWords, kinds: kinds.union(other.kinds), period: period ?? other.period)
    }

    private static let periodPhrases: [(words: [String], period: Period)] = [
        (["gecen", "hafta"], .lastWeek), (["gecen", "haftaki"], .lastWeek), (["bu", "hafta"], .thisWeek),
        (["bu", "haftaki"], .thisWeek), (["gecen", "ay"], .lastMonth), (["gecen", "ayki"], .lastMonth),
        (["bu", "ay"], .thisMonth), (["bu", "ayki"], .thisMonth), (["last", "week"], .lastWeek),
        (["this", "week"], .thisWeek), (["last", "month"], .lastMonth), (["this", "month"], .thisMonth),
        (["bugun"], .today), (["bugunku"], .today), (["today"], .today), (["todays"], .today), (["dun"], .yesterday),
        (["dunku"], .yesterday), (["yesterday"], .yesterday), (["yesterdays"], .yesterday),
    ]
    private static let requestWords: Set<String> = [
        "dosya", "dosyasi", "dosyasini", "dosyayi", "dosyalari", "dosyalarimi", "dosyam", "dosyami", "belge", "belgesi",
        "belgesini", "belgeyi", "belgeler", "dokuman", "son", "en", "olan", "adli", "isimli", "bul", "ac", "goster",
        "benim", "bir", "file", "files", "document", "documents", "the", "my", "a", "latest", "last", "newest",
        "downloaded", "named", "called", "find", "open", "show", "from", "of", "in",
    ]
    /// "İndirdiğim", "kaydettiğim": how the file came to be, not part of its name.
    private static let participleEndings = ["digim", "dugum", "tigim", "tugum", "digimiz", "dugumuz"]

    public static func parse(_ text: String) -> FileQuery {
        // "Ahmet'in raporu": the name before the apostrophe; "rapor.pdf": the name and its kind.
        let tokens = text.split(whereSeparator: \.isWhitespace)
            .map { String($0.split(whereSeparator: { $0 == "'" || $0 == "’" }).first ?? "") }
            .flatMap { String($0.map { $0.isLetter || $0.isNumber ? $0 : " " }).split(separator: " ").map(String.init) }
        let folded = tokens.map { TurkishText.folded($0) }
        var kinds = Set<Kind>()
        var period: Period?
        var nameWords: [String] = []
        var index = 0
        while index < tokens.count {
            if let phrase = periodPhrases.first(where: { Array(folded[index..<min(index + $0.words.count, folded.count)]) == $0.words }) {
                period = period ?? phrase.period
                index += phrase.words.count
                continue
            }
            let word = folded[index]
            if let kind = Kind.allCases.first(where: { $0.stems.contains(where: word.hasPrefix) }) {
                kinds.insert(kind)
            } else if !requestWords.contains(word), !word.hasPrefix("indir"), !participleEndings.contains(where: word.hasSuffix) {
                nameWords.append(tokens[index])
            }
            index += 1
        }
        return FileQuery(nameWords: nameWords, kinds: kinds, period: period)
    }

    /// Spoken words that parse back to this query, so a refined search can travel as text.
    public var text: String {
        let kindWords = Kind.allCases.filter(kinds.contains).map(\.stems[0])
        let periodWords = period.flatMap { period in Self.periodPhrases.first { $0.period == period }?.words } ?? []
        return (nameWords + kindWords + periodWords).joined(separator: " ")
    }

    /// For `mdfind`: every name word somewhere in the file name (ignoring case and accents), one of the
    /// kinds' extensions, and the change date in the period.
    public var spotlightQuery: String {
        var conditions = nameWords.map { "kMDItemFSName == \"*\($0)*\"cd" }
        if !kinds.isEmpty {
            let names = extensions.sorted().map { "kMDItemFSName == \"*.\($0)\"c" }
            conditions.append("(" + names.joined(separator: " || ") + ")")
        }
        if let period { conditions.append(Self.dateCondition(period)) }
        return conditions.joined(separator: " && ")
    }

    private static func dateCondition(_ period: Period) -> String {
        let date = "kMDItemFSContentChangeDate"
        return switch period {
        case .today: "\(date) >= $time.today"
        case .yesterday: "\(date) >= $time.yesterday && \(date) < $time.today"
        case .thisWeek: "\(date) >= $time.this_week"
        case .lastWeek: "\(date) >= $time.this_week(-1) && \(date) < $time.this_week"
        case .thisMonth: "\(date) >= $time.this_month"
        case .lastMonth: "\(date) >= $time.this_month(-1) && \(date) < $time.this_month"
        }
    }
}
