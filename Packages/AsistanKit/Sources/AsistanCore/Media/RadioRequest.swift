import Foundation

public enum RadioCommand: Sendable, Equatable {
    /// A station by the name to search for; nil plays the last one.
    case play(station: String?)
    case stop
    case resume
    case nowPlaying
    case volume(louder: Bool)
}

/// What the in-app player is doing, which decides whether "durdur" or "sesini kıs" are about it.
public enum StreamState: Sendable, Equatable {
    case idle, playing, paused
}

/// "Power FM aç", "radyoyu kapat", "radyonun sesini kıs", "hangi radyo çalıyor"; "play Virgin Radio", "turn off the radio".
/// A name without a radio word ("Tarkan çal") is left to the music tools unless it is a known station.
public enum RadioRequest {
    private static let playVerbs: Set<String> = [
        "ac", "acar", "acsana", "acabilir", "acin", "cal", "calar", "calsana", "calabilir", "calin", "baslat", "baslatir",
        "dinlet", "dinle", "koy", "oynat",
    ]
    private static let stopVerbs: Set<String> = ["kapat", "kapa", "kapatir", "durdur", "durdurur", "duraklat", "sustur", "kes"]
    private static let quieter: Set<String> = ["kis", "kisar", "azalt", "dusur", "alcalt"]
    private static let louder: Set<String> = ["ac", "acar", "artir", "arttir", "yukselt"]
    private static let politeness: Set<String> = ["misin", "musun", "misiniz", "musunuz", "lutfen", "hemen", "simdi"]
    private static let leadingFillers: Set<String> = ["bana", "biraz", "bir", "lutfen", "hadi", "simdi", "su", "bi"]
    /// "TRT FM'in sitesini aç" opens a website, not the stream.
    private static let otherObjects: Set<String> = [
        "sitesi", "sitesini", "sayfasi", "sayfasini", "uygulamasi", "uygulamasini", "uygulama", "web", "haberleri", "frekansi",
    ]
    private static let nowPlayingWords: Set<String> = ["caliyor", "acik", "bu", "dinliyorum", "dinliyoruz", "calan", "yayinda"]
    /// "30 dakika sonra radyoyu kapat" is for later; there is no sleep timer, so it is left to the other tools.
    private static let delayWords: Set<String> = ["sonra", "kadar", "later", "after"]
    private static let delayStems = ["dakika", "saniye", "saat", "minute", "second", "hour"]

    public static func parse(_ text: String, language: AssistantLanguage = .turkish, stream: StreamState = .idle) -> RadioCommand? {
        let tokens = SpokenToken.split(text)
        guard !tokens.isEmpty, !tokens.contains(where: { isDelayWord($0.folded) }) else { return nil }
        return language == .english ? english(tokens, stream: stream) : turkish(tokens, stream: stream)
    }

    // MARK: - Turkish

    private static func turkish(_ all: [SpokenToken], stream: StreamState) -> RadioCommand? {
        var tokens = all
        while let last = tokens.last, tokens.count > 1, politeness.contains(last.folded) { tokens.removeLast() }
        let words = tokens.map(\.folded)
        if stream != .idle, let command = bareStreamCommand(words, stream: stream) { return command }
        let mentionsRadio = words.contains(where: isRadioWord)
        if mentionsRadio, words.contains(where: { $0 == "hangi" || $0 == "ne" }),
           words.contains(where: nowPlayingWords.contains), !words.contains(where: playVerbs.contains) {
            return .nowPlaying
        }
        if mentionsRadio, let verb = words.last {
            if quieter.contains(verb) { return .volume(louder: false) }
            if louder.contains(verb), words.contains(where: { $0.hasPrefix("ses") }) { return .volume(louder: true) }
            if stopVerbs.contains(verb) { return .stop }
        }
        let wantsToListen = words.count >= 3 && words.suffix(2) == ["dinlemek", "istiyorum"]
        guard wantsToListen || words.last.map(playVerbs.contains) == true else { return nil }
        var body = Array(tokens.dropLast(wantsToListen ? 2 : 1))
        while let first = body.first, body.count > 1, leadingFillers.contains(first.folded) { body.removeFirst() }
        return station(in: body, mentionsRadio: mentionsRadio)
    }

    /// "Durdur", "devam et" and "sesini kıs" said while the in-app player has something.
    private static func bareStreamCommand(_ words: [String], stream: StreamState) -> RadioCommand? {
        if [["durdur"], ["duraklat"], ["sustur"]].contains(words) { return .stop }
        if stream == .paused, [["devam", "et"], ["devam"], ["devam", "ettir"], ["kaldigin", "yerden", "devam", "et"]].contains(words) {
            return .resume
        }
        let rest = words.filter { $0 != "biraz" }
        guard rest.count == 2, rest[0] == "sesini" else { return nil }
        if quieter.contains(rest[1]) { return .volume(louder: false) }
        if louder.contains(rest[1]) { return .volume(louder: true) }
        return nil
    }

    // MARK: - English

    private static let englishRadioWords: Set<String> = ["radio", "fm", "station"]
    private static let englishPlayLeads: [[String]] = [["play"], ["put", "on"], ["turn", "on"], ["switch", "on"], ["listen", "to"], ["open"], ["start"]]
    private static let englishFillers: Set<String> = ["the", "some", "a", "please", "me"]

    private static func english(_ tokens: [SpokenToken], stream: StreamState) -> RadioCommand? {
        let words = tokens.map(\.folded).filter { $0 != "please" }
        if stream != .idle {
            if [["stop"], ["pause"], ["stop", "it"], ["pause", "it"]].contains(words) { return .stop }
            if stream == .paused, [["resume"], ["unpause"], ["keep", "playing"], ["continue", "playing"]].contains(words) { return .resume }
            if [["turn", "it", "down"], ["quieter"], ["lower", "the", "volume"]].contains(words) { return .volume(louder: false) }
            if [["turn", "it", "up"], ["louder"]].contains(words) { return .volume(louder: true) }
        }
        let mentionsRadio = words.contains(where: englishRadioWords.contains)
        if mentionsRadio {
            if words.contains(where: { $0 == "which" || $0 == "what" || $0 == "whats" }), !words.contains("play") { return .nowPlaying }
            if words.contains("down") || words.contains("quieter") { return .volume(louder: false) }
            if words.contains("louder") || (words.contains("up") && words.contains("turn")) { return .volume(louder: true) }
            if words.contains("stop") || words.contains("off") || words.contains("pause") { return .stop }
        }
        guard let lead = englishPlayLeads.first(where: { words.starts(with: $0) }) else { return nil }
        var body = Array(tokens.filter { $0.folded != "please" }.dropFirst(lead.count))
        while let first = body.first, englishFillers.contains(first.folded) { body.removeFirst() }
        return station(in: body, mentionsRadio: mentionsRadio)
    }

    // MARK: - Station names

    private static func station(in body: [SpokenToken], mentionsRadio: Bool) -> RadioCommand? {
        guard !body.isEmpty else { return nil }
        let folded = body.map(\.folded)
        if folded.contains(where: otherObjects.contains) { return nil }
        let names = body.map(\.stem)
        if names.count == 1, isRadioWord(TurkishText.folded(names[0])) || ["station"].contains(folded[0]) { return .play(station: nil) }
        let phrase = names.joined(separator: " ")
        if let entry = PopularRadioStations.entry(named: phrase) { return .play(station: entry.name) }
        guard mentionsRadio else { return nil }
        let normalized = names.map(normalizedRadioWord).joined(separator: " ")
        if let entry = PopularRadioStations.entry(named: normalized) { return .play(station: entry.name) }
        return .play(station: normalized)
    }

    private static func isDelayWord(_ folded: String) -> Bool {
        delayWords.contains(folded) || delayStems.contains(where: folded.hasPrefix)
    }

    /// "radyo", "radyoyu", "radyonun", "radio", "fm", "fm'i" and the like.
    private static func isRadioWord(_ folded: String) -> Bool {
        folded.hasPrefix("radyo") || folded.hasPrefix("radio") || folded == "fm" || (folded.hasPrefix("fm") && folded.count <= 4)
    }

    /// "Radioyu" said without an apostrophe is still "Radio".
    private static func normalizedRadioWord(_ word: String) -> String {
        let folded = TurkishText.folded(word)
        if folded.hasPrefix("radyo") && folded != "radyo" && folded.count <= 9 { return "Radyo" }
        if folded.hasPrefix("radio") && folded != "radio" && folded.count <= 9 { return "Radio" }
        if folded.hasPrefix("fm") && folded.count <= 4 { return "FM" }
        return word
    }
}
