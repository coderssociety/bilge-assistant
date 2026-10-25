/// Note requests read from the words themselves: adding to an existing note ("alışveriş notuma süt ekle",
/// "toplantı notuna şunu ekle: …") and listing notes ("notlarım neler", "son notlarım"). The text to add is
/// kept exactly as the user said it.
public enum NoteRequest {
    public struct Addition: Equatable, Sendable {
        /// The note's name as said, without the "notuma" word: "alışveriş".
        public let note: String
        public let text: String
    }

    private static let noteWords: Set<String> = [
        "notuma", "notuna", "notumuza", "notlarima", "notlarina", "notunun", "notumun",
    ]
    /// "Toplantı notunun sonuna ekle".
    private static let endWords: Set<String> = ["sonuna", "altina"]
    private static let addStems = ["ekle", "ilave", "kaydet"]
    private static let writeVerbs: Set<String> = ["yaz", "yazar", "yazsana", "yazabilir", "yazin", "yaziver"]
    private static let pointers: Set<String> = ["sunu", "bunu", "sunlari", "bunlari"]
    private static let textEnds: Set<String> = ["diye", "olarak"]
    private static let leadingFillers: Set<String> = ["lutfen", "bilge", "benim", "bir", "please", "my", "the", "our"]

    public static func addition(in command: String, language: AssistantLanguage = .turkish) -> Addition? {
        let words = SpokenWords(command)
        return language == .english ? englishAddition(words) : turkishAddition(words)
    }

    private static func turkishAddition(_ words: SpokenWords) -> Addition? {
        let folded = words.folded
        guard let noteIndex = folded.firstIndex(where: noteWords.contains) else { return nil }
        let end = words.contentEnd
        guard let verb = (noteIndex + 1..<max(noteIndex + 1, end)).first(where: { isAddVerb(folded[$0]) }) else { return nil }
        let start = noteIndex + 1 < verb && endWords.contains(folded[noteIndex + 1]) ? noteIndex + 2 : noteIndex + 1
        var before = Array(start..<verb)
        while let first = before.first, pointers.contains(folded[first]) { before.removeFirst() }
        while let last = before.last, textEnds.contains(folded[last]) { before.removeLast() }
        // "…notuna şunu ekle: …" puts the text after the verb; otherwise it sits between the note and the verb.
        let after = verb + 1 < end ? Array(verb + 1..<end) : []
        let range = before.isEmpty ? after : before
        guard let first = range.first, let last = range.last else { return nil }
        return addition(note: name(words, upTo: noteIndex), text: words.text(first..<last + 1))
    }

    private static func isAddVerb(_ word: String) -> Bool {
        addStems.contains(where: word.hasPrefix) || writeVerbs.contains(word)
    }

    private static let englishVerbs: Set<String> = ["add", "append", "put", "write", "jot"]
    private static let englishPlaces: Set<String> = ["to", "in", "into", "on", "onto"]

    /// "Add milk to my shopping note", "append the budget is approved to the meeting note",
    /// "add to my shopping note: eggs".
    private static func englishAddition(_ words: SpokenWords) -> Addition? {
        let folded = words.folded
        guard let verb = folded.firstIndex(where: englishVerbs.contains),
              let note = folded.indices.first(where: { $0 > verb && (folded[$0] == "note" || folded[$0] == "notes") }),
              let place = (verb + 1..<note).last(where: { englishPlaces.contains(folded[$0]) })
        else { return nil }
        let end = words.contentEnd
        var text = Array(verb + 1..<place)
        if text.first.map({ folded[$0] == "down" }) == true { text.removeFirst() }
        if text.isEmpty, note + 1 < end { text = Array(note + 1..<end) }
        while let first = text.first, folded[first] == "that" { text.removeFirst() }
        guard let first = text.first, let last = text.last else { return nil }
        return addition(note: name(words, from: place + 1, upTo: note), text: words.text(first..<last + 1))
    }

    private static func name(_ words: SpokenWords, from start: Int = 0, upTo end: Int) -> String {
        var first = start
        while first < end, leadingFillers.contains(words.folded[first]) { first += 1 }
        return words.text(first..<end)
    }

    private static func addition(note: String, text: String) -> Addition? {
        guard !note.isEmpty, !text.isEmpty else { return nil }
        return Addition(note: note, text: text)
    }

    private static let pluralNotes: Set<String> = ["notlarim", "notlarimi", "notlar", "notlari", "notlarimiz"]
    private static let listCues: Set<String> = ["neler", "ne", "listele", "hangi", "hangileri", "son", "say", "goster", "oku"]
    private static let englishListCues: Set<String> = ["list", "what", "which", "show", "recent", "latest", "last", "my"]
    private static let englishNotList: Set<String> = ["open", "about", "delete", "add"]

    /// "Notlarım neler", "son notlarım", "hangi notlarım var"; "list my notes", "my recent notes".
    /// One note ("son notumu oku") or opening the app ("notlarımı aç") is not a list.
    public static func asksForList(_ command: String, language: AssistantLanguage = .turkish) -> Bool {
        let words = Set(TurkishText.folded(command).split(separator: " ").map(String.init))
        if language == .english {
            return words.contains("notes") && !words.isDisjoint(with: englishListCues) && words.isDisjoint(with: englishNotList)
        }
        return !words.isDisjoint(with: pluralNotes) && !words.isDisjoint(with: listCues)
    }
}
