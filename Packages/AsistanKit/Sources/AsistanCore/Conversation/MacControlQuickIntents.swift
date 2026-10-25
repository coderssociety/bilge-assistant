/// Fast-path phrases for brightness, Bluetooth, Focus, power and playback. Same contract as
/// QuickIntentParser: exact phrasings only, anything else goes to the model.
enum MacControlQuickIntents {
    private static let upVerbs: Set<String> = ["artir", "arttir", "yukselt", "ac"]
    private static let downVerbs: Set<String> = ["azalt", "dusur", "kis", "alcalt"]
    private static let setVerbs: Set<String> = ["yap", "getir", "ayarla", "cek", "indir", "cikar"]
    private static let mediaSubjects: Set<String> = ["sarkiyi", "videoyu", "muzigi", "parcayi", "podcasti", "bolumu"]
    private static let secondsPerMinute = 60
    private static let maxPercent = 100

    static func parse(_ w: [String]) -> QuickIntent? {
        brightness(w) ?? bluetooth(w) ?? focus(w) ?? power(w) ?? playback(w)
    }

    private static func brightness(_ w: [String]) -> QuickIntent? {
        if w == ["ekrani", "parlat"] { return .brightness(.up) }
        let subjects: [[String]] = [["parlakligi"], ["ekran", "parlakligini"], ["ekranin", "parlakligini"]]
        guard let subject = subjects.first(where: { w.count > $0.count && Array(w.prefix($0.count)) == $0 }) else { return nil }
        let rest = Array(w.dropFirst(subject.count))
        if rest == ["sonuna", "kadar", "ac"] || rest == ["sonuna", "kadar", "artir"] { return .brightness(.set(maxPercent)) }
        let body = rest.first == "biraz" ? Array(rest.dropFirst()) : rest
        if body.count == 1, let verb = body.first {
            if upVerbs.contains(verb) { return .brightness(.up) }
            if downVerbs.contains(verb) { return .brightness(.down) }
            return nil
        }
        guard let verb = rest.last, let amount = rest.dropLast().compactMap(leadingNumber).first,
              rest.dropLast().allSatisfy({ $0 == "yuzde" || leadingNumber($0) != nil }) else { return nil }
        let percent = min(amount, maxPercent)
        if setVerbs.contains(verb) { return .brightness(.set(percent)) }
        if upVerbs.contains(verb) { return .brightness(.change(percent)) }
        return downVerbs.contains(verb) ? .brightness(.change(-percent)) : nil
    }

    private static func bluetooth(_ w: [String]) -> QuickIntent? {
        guard let subject = w.first, ["bluetooth", "bluetoothu"].contains(subject) else { return nil }
        switch Array(w.dropFirst()) {
        case ["ac"]: return .bluetooth(.on)
        case ["kapat"]: return .bluetooth(.off)
        case ["acik", "mi"], ["kapali", "mi"], ["durumu"], ["durumu", "ne"], ["acik", "mi", "kapali", "mi"]:
            return subject == "bluetooth" ? .bluetooth(.status) : nil
        default: return nil
        }
    }

    private static func focus(_ w: [String]) -> QuickIntent? {
        let subjects: Set<[String]> = [
            ["rahatsiz", "etme", "modunu"], ["rahatsiz", "etmeyin", "modunu"], ["rahatsiz", "etmeyi"], ["rahatsiz", "etmeyin"],
            ["odak", "modunu"], ["odagi"], ["odaklanma", "modunu"],
        ]
        guard let verb = w.last, subjects.contains(Array(w.dropLast())) else { return nil }
        switch verb {
        case "ac": return .system(.focusOn)
        case "kapat": return .system(.focusOff)
        default: return nil
        }
    }

    private static func power(_ w: [String]) -> QuickIntent? {
        let logOut: Set<[String]> = [["oturumu", "kapat"], ["oturumdan", "cik"], ["oturumu", "sonlandir"]]
        if logOut.contains(w) { return .system(.logOut) }
        guard let subject = w.first, ["bilgisayari", "maci"].contains(subject) else { return nil }
        switch Array(w.dropFirst()) {
        case ["yeniden", "baslat"]: return .system(.restart)
        case ["kapat"], ["tamamen", "kapat"]: return .system(.shutDown)
        default: return nil
        }
    }

    private static func playback(_ w: [String]) -> QuickIntent? {
        let body = w.first.map(mediaSubjects.contains) == true ? Array(w.dropFirst()) : w
        let toggles: [[String]: QuickIntent.Media] = [
            ["karistirmayi", "ac"]: .shuffle(true), ["karisik", "cal"]: .shuffle(true), ["karisik", "calmayi", "ac"]: .shuffle(true),
            ["karistirmayi", "kapat"]: .shuffle(false), ["karisik", "calmayi", "kapat"]: .shuffle(false),
            ["tekrari", "ac"]: .repeatAll(true), ["tekrarlamayi", "ac"]: .repeatAll(true), ["tekrarla"]: .repeatAll(true),
            ["tekrari", "kapat"]: .repeatAll(false), ["tekrarlamayi", "kapat"]: .repeatAll(false),
            ["bastan", "baslat"]: .restartTrack, ["bastan", "cal"]: .restartTrack, ["basa", "sar"]: .restartTrack,
        ]
        if let media = toggles[body], body != ["tekrarla"] || w.first == "sarkiyi" { return .media(media) }
        guard body.count >= 2, body.last == "sar", ["ileri", "geri"].contains(body[body.count - 2]) else { return nil }
        let forward = body[body.count - 2] == "ileri"
        let amount = Array(body.dropLast(2))
        let seconds: Int?
        switch amount.count {
        case 0: seconds = nil
        case 1 where amount[0] == "biraz": seconds = nil
        case 2:
            guard let value = Int(amount[0]) else { return nil }
            switch amount[1] {
            case "saniye": seconds = value
            case "dakika": seconds = value * secondsPerMinute
            default: return nil
            }
        default: return nil
        }
        return .media(forward ? .seekForward(seconds) : .seekBackward(seconds))
    }

    private static func leadingNumber(_ word: String) -> Int? {
        let digits = word.prefix(while: \.isNumber)
        return digits.isEmpty ? nil : Int(digits)
    }
}
