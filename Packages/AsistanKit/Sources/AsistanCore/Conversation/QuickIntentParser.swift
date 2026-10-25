/// Everyday commands recognized by rule, skipping both model calls (~1.2 s). The rules are narrow
/// on purpose: anything with extra content (a label, a second action, an unknown word) returns nil
/// and goes to the model, so the fast path can only be faster, never wronger.
public enum QuickIntent: Sendable, Equatable {
    public enum Volume: Sendable, Equatable { case set(Int), up, down, change(Int), mute, unmute }
    public enum Media: Sendable, Equatable {
        case play, pause, next, previous, nowPlaying, restartTrack
        /// Seconds; nil when not said.
        case seekForward(Int?), seekBackward(Int?)
        case shuffle(Bool), repeatAll(Bool)
    }
    public enum System: Sendable, Equatable {
        case lockScreen, screenOff, sleep, darkModeOn, darkModeOff, focusOn, focusOff, restart, shutDown, logOut
    }
    public enum CalendarRange: Sendable, Equatable { case today, tomorrow, thisWeek }
    public enum Folder: Sendable, Equatable { case desktop, downloads, documents }
    public enum TimerAction: Sendable, Equatable { case list, cancelOne, cancelAll }

    case dateTime
    case battery
    case reminders
    case clipboard
    case openFolder(Folder)
    case timers(TimerAction)
    case volume(Volume)
    case media(Media)
    case system(System)
    case calendar(CalendarRange)
    case calculate(String)
    case timer(seconds: Int)
    case alarm(hour: Int, minute: Int)
    case openApp(String)
    case quitApp(String)
    case screenshot
    case wifi(on: Bool)
    case window(Window)
    case settings(SettingsPane)
    case systemInfo(SystemInfoTopic)
    case brightness(Brightness)
    case bluetooth(Bluetooth)
}

public enum QuickIntentParser {
    private static let maxAppNameWords = 3

    /// `text` should already be digitized and time-resolved (TurkishNumberParser, TurkishTimeOfDay).
    public static func parse(_ text: String) -> QuickIntent? {
        let original = text.split(whereSeparator: \.isWhitespace).map { String($0).trimmingCharacters(in: .punctuationCharacters.subtracting(["'"])) }
            .filter { !$0.isEmpty }
        let (words, kept) = simplified(original.map(TurkishText.folded), original)
        guard !words.isEmpty else { return nil }
        let wordRules: [([String]) -> QuickIntent?] = [
            dateTime, battery, volume, media, system, calendar, reminders, clipboard, folder, timers,
        ]
        for rule in wordRules {
            if let intent = rule(words) { return intent }
        }
        if let intent = MacQuickIntents.parse(words) { return intent }
        if let intent = timer(words, text: text) { return intent }
        if let expression = TurkishArithmeticParser.expression(from: text) { return .calculate(expression) }
        return app(words, original: kept)
    }

    // MARK: - Politeness

    /// Question-form verbs this parser knows, mapped to the imperative its rules expect
    /// ("kilitler misin" → "kilitle"). Unknown verbs stay as they are and fall through to the model.
    private static let aoristToImperative: [String: String] = [
        "kilitler": "kilitle", "gecer": "gec", "acar": "ac", "kapatir": "kapat", "okur": "oku", "baslatir": "baslat",
        "durdurur": "durdur", "duraklatir": "duraklat", "kisar": "kis", "artirir": "artir", "yukseltir": "yukselt",
        "azaltir": "azalt", "soyler": "soyle", "listeler": "listele", "kurar": "kur", "uyutur": "uyut", "alir": "al",
        "calar": "cal", "getirir": "getir", "yapar": "yap", "gosterir": "goster", "eder": "et", "siler": "sil",
    ]
    private static let questionParticles: Set<String> = ["misin", "musun", "misiniz", "musunuz"]
    private static let trailingPoliteness: Set<String> = ["lutfen", "acaba", "hemen"]
    private static let leadingPoliteness: Set<String> = ["simdi", "hemen", "lutfen"]

    /// Drops "şu an", "lütfen", "acaba" and turns "…ar mısın" into an imperative, on folded words
    /// and the matching original tokens alike (app names are taken from the originals).
    private static func simplified(_ words: [String], _ original: [String]) -> ([String], [String]) {
        var pairs = Array(zip(words, original))
        if pairs.count > 2, pairs[0].0 == "su", pairs[1].0 == "an" { pairs.removeFirst(2) }
        while let first = pairs.first, pairs.count > 1, leadingPoliteness.contains(first.0) { pairs.removeFirst() }
        while let last = pairs.last, pairs.count > 1, trailingPoliteness.contains(last.0) { pairs.removeLast() }
        if pairs.count >= 2, let last = pairs.last, questionParticles.contains(last.0),
           let imperative = aoristToImperative[pairs[pairs.count - 2].0] {
            pairs.removeLast()
            pairs[pairs.count - 1] = (imperative, imperative)
        }
        return (pairs.map(\.0), pairs.map(\.1))
    }

    // MARK: - Rules

    private static func dateTime(_ w: [String]) -> QuickIntent? {
        let phrases: [[String]] = [
            ["saat", "kac"], ["saat", "kac", "oldu"], ["saat", "kac", "acaba"], ["saat", "kac", "oldu", "acaba"],
            ["bugun", "gunlerden", "ne"], ["tarih", "ne"], ["bugunun", "tarihi", "ne"], ["ayin", "kaci"],
            ["bugun", "ayin", "kaci"], ["bugun", "ne", "gunu"],
        ]
        return phrases.contains(w) ? .dateTime : nil
    }

    private static func battery(_ w: [String]) -> QuickIntent? {
        let allowed: Set<String> = ["durumu", "durum", "kac", "ne", "kadar", "nedir", "durumda", "yuzde", "seviyesi", "oldu"]
        guard w.count <= 5, ["pil", "sarj", "batarya"].contains(where: w[0].hasPrefix),
              w.dropFirst().allSatisfy(allowed.contains) else { return nil }
        return .battery
    }

    private static func volume(_ w: [String]) -> QuickIntent? {
        if w == ["sessize", "al"] { return .volume(.mute) }
        guard w.first == "sesi", w.count >= 2, w.count <= 4 else { return nil }
        let setVerbs: Set<String> = ["yap", "getir", "ayarla", "indir", "cek", "dusur", "cikar"]
        let upVerbs: Set<String> = ["artir", "arttir", "yukselt"]
        let downVerbs: Set<String> = ["kis", "azalt", "dusur", "alcalt"]
        let rest = Array(w.dropFirst())
        if let verb = rest.last, upVerbs.contains(verb) || downVerbs.contains(verb),
           let amount = rest.dropLast().compactMap({ Int($0) }).first,
           rest.dropLast().allSatisfy({ ["yuzde", "puan"].contains($0) || Int($0) != nil }) {
            return .volume(.change(upVerbs.contains(verb) ? min(amount, 100) : -min(amount, 100)))
        }
        if let verb = rest.last, setVerbs.contains(verb), let level = rest.dropLast().compactMap(leadingNumber).first,
           rest.dropLast().allSatisfy({ $0 == "yuzde" || leadingNumber($0) != nil }) {
            return .volume(.set(min(level, 100)))
        }
        switch rest {
        case ["kapat"]: return .volume(.mute)
        case ["ac"]: return .volume(.unmute)
        case ["biraz", "ac"]: return .volume(.up)
        default: break
        }
        let body = rest.first == "biraz" ? Array(rest.dropFirst()) : rest
        guard body.count == 1, let verb = body.first else { return nil }
        if upVerbs.contains(verb) { return .volume(.up) }
        if downVerbs.contains(verb) { return .volume(.down) }
        return nil
    }

    private static func media(_ w: [String]) -> QuickIntent? {
        let subject: Set<String> = ["muzigi", "sarkiyi", "calmayi"]
        if w.count == 2, subject.contains(w[0]) {
            switch w[1] {
            case "durdur", "duraklat": return .media(.pause)
            case "baslat", "cal", "ac": return w[0] == "muzigi" ? .media(.play) : nil
            case "gec", "degistir": return w[0] == "sarkiyi" ? .media(.next) : nil
            default: return nil
            }
        }
        let next: [[String]] = [["sonraki", "sarkiya", "gec"], ["sonraki", "sarki"], ["siradaki", "sarki"],
                                ["sonraki", "parca"], ["sonraki", "sarkiyi", "cal"], ["siradaki", "sarkiya", "gec"]]
        if next.contains(w) { return .media(.next) }
        let previous: [[String]] = [["onceki", "sarki"], ["bir", "onceki", "sarkiyi", "cal"], ["onceki", "sarkiyi", "cal"],
                                    ["onceki", "sarkiya", "don"], ["onceki", "parca"]]
        if previous.contains(w) { return .media(.previous) }
        let nowPlaying: [[String]] = [["bu", "sarkinin", "adi", "ne"], ["calan", "sarki", "ne"], ["bu", "hangi", "sarki"],
                                      ["calan", "sarki", "hangisi"], ["ne", "caliyor"], ["su", "an", "ne", "caliyor"]]
        return nowPlaying.contains(w) ? .media(.nowPlaying) : nil
    }

    private static func system(_ w: [String]) -> QuickIntent? {
        if w.last == "kilitle", w.count <= 2, w.count == 1 || ["ekrani", "maci", "bilgisayari"].contains(w[0]) {
            return .system(.lockScreen)
        }
        let screenOff: [[String]] = [["ekrani", "karart"], ["ekrani", "kapat"], ["ekrani", "uyut"]]
        if screenOff.contains(w) { return .system(.screenOff) }
        let sleep: [[String]] = [["bilgisayari", "uyut"], ["maci", "uyut"], ["uyku", "moduna", "al"],
                                 ["bilgisayari", "uyku", "moduna", "al"], ["maci", "uyku", "moduna", "al"]]
        if sleep.contains(w) { return .system(.sleep) }
        let darkOn: [[String]] = [["karanlik", "modu", "ac"], ["karanlik", "moda", "gec"], ["koyu", "moda", "gec"],
                                  ["karanlik", "mod"], ["koyu", "modu", "ac"]]
        if darkOn.contains(w) { return .system(.darkModeOn) }
        let darkOff: [[String]] = [["aydinlik", "moda", "gec"], ["karanlik", "modu", "kapat"], ["acik", "moda", "gec"],
                                   ["aydinlik", "modu", "ac"], ["aydinlik", "mod"]]
        return darkOff.contains(w) ? .system(.darkModeOff) : nil
    }

    private static func calendar(_ w: [String]) -> QuickIntent? {
        let isCalendarWord: (String) -> Bool = { $0.hasPrefix("takvim") }
        let tail: Set<[String]> = [["ne", "var"], ["neler", "var"]]
        func matches(_ prefix: [String]) -> Bool {
            guard w.count >= prefix.count + 2, Array(w.prefix(prefix.count)) == prefix else { return false }
            let middle = w.dropFirst(prefix.count).dropLast(2)
            return middle.count <= 1 && middle.allSatisfy(isCalendarWord) && tail.contains(Array(w.suffix(2)))
        }
        if matches(["bugun"]) { return .calendar(.today) }
        if matches(["yarin"]) { return .calendar(.tomorrow) }
        if matches(["bu", "hafta"]) { return .calendar(.thisWeek) }
        return nil
    }

    private static func reminders(_ w: [String]) -> QuickIntent? {
        let subjects: Set<String> = ["animsaticilarimi", "animsaticilari", "yapilacaklarimi", "yapilacaklari"]
        let verbs: Set<String> = ["oku", "soyle", "listele"]
        if w.count == 2, subjects.contains(w[0]), verbs.contains(w[1]) { return .reminders }
        if w.count == 3, w[0] == "yapilacaklar", w[1] == "listemi", verbs.contains(w[2]) { return .reminders }
        return nil
    }

    private static func clipboard(_ w: [String]) -> QuickIntent? {
        let phrases: [[String]] = [["panoyu", "oku"], ["panoda", "ne", "var"]]
        if phrases.contains(w) { return .clipboard }
        guard w.count == 3, ["panodaki", "kopyaladigim"].contains(w[0]), ["metni", "yaziyi", "seyi"].contains(w[1]),
              ["oku", "soyle"].contains(w[2]) else { return nil }
        return .clipboard
    }

    private static func folder(_ w: [String]) -> QuickIntent? {
        let folders: [String: QuickIntent.Folder] = [
            "masaustunu": .desktop, "masaustu": .desktop, "indirilenleri": .downloads, "indirilenler": .downloads,
            "belgeleri": .documents, "belgeler": .documents, "dokumanlari": .documents, "dokumanlar": .documents,
        ]
        guard w.last == "ac", (2...3).contains(w.count), let target = folders[w[0]] else { return nil }
        guard w.count == 2 || ["klasorunu", "klasoru"].contains(w[1]) else { return nil }
        return .openFolder(target)
    }

    private static func timers(_ w: [String]) -> QuickIntent? {
        let subjects: Set<String> = ["alarmlari", "zamanlayicilari", "alarmlarimi", "zamanlayicilarimi"]
        let body = ["butun", "tum"].contains(w.first ?? "") ? Array(w.dropFirst()) : w
        if let subject = body.first, subjects.contains(subject) {
            let verb = Array(body.dropFirst())
            if [["kapat"], ["sil"], ["iptal", "et"], ["iptal"]].contains(verb) { return .timers(.cancelAll) }
            if verb == ["listele"] || verb == ["oku"] { return .timers(.list) }
        }
        let singular: Set<String> = ["zamanlayiciyi", "alarmi"]
        if body.count >= 2, w == body, singular.contains(body[0]),
           [["kapat"], ["sil"], ["iptal", "et"], ["durdur"]].contains(Array(body.dropFirst())) {
            return .timers(.cancelOne)
        }
        let listPhrases: [[String]] = [["kurulu", "zamanlayicilar", "neler"], ["kurulu", "alarmlar", "neler"],
                                       ["hangi", "alarmlar", "kurulu"], ["hangi", "zamanlayicilar", "kurulu"],
                                       ["kac", "dakika", "kaldi"], ["kac", "saniye", "kaldi"],
                                       ["zamanlayicida", "ne", "kadar", "kaldi"], ["zamanlayicida", "kac", "dakika", "kaldi"],
                                       ["zamanlayicinin", "bitmesine", "ne", "kadar", "kaldi"], ["alarma", "ne", "kadar", "kaldi"]]
        return listPhrases.contains(w) ? .timers(.list) : nil
    }

    /// Only bare timers and wake-up alarms; "çayı hatırlat" carries a label, so the model handles it.
    private static func timer(_ w: [String], text: String) -> QuickIntent? {
        let triggers: Set<String> = ["zamanlayici", "zamanlayicisi", "alarm", "uyar", "uyandir"]
        let allowed: Set<String> = triggers.union([
            "dakika", "dakikalik", "saniye", "saniyelik", "saat", "saatlik", "sonra", "kur", "baslat", "ayarla",
            "beni", "bucuk", "yarin", "bir", "yarim", "ceyrek",
        ])
        guard w.contains(where: triggers.contains),
              w.allSatisfy({ allowed.contains($0) || leadingNumber($0) != nil }),
              let parsed = TimerPhraseParser.parse(text) else { return nil }
        if let hour = parsed.hour { return .alarm(hour: hour, minute: parsed.minute ?? 0) }
        return parsed.durationSeconds.map { .timer(seconds: $0) }
    }

    private static func app(_ w: [String], original: [String]) -> QuickIntent? {
        let openEndings: [[String]] = [["ac"], ["baslat"], ["acar", "misin"], ["acsana"], ["acabilir", "misin"]]
        let quitEndings: [[String]] = [["kapat"], ["kapatir", "misin"], ["kapatsana"], ["kapatabilir", "misin"]]
        for (endings, make) in [(openEndings, QuickIntent.openApp), (quitEndings, QuickIntent.quitApp)] {
            for ending in endings where w.count > ending.count && Array(w.suffix(ending.count)) == ending {
                var nameWords = Array(original.dropLast(ending.count))
                if let last = nameWords.last.map(TurkishText.folded), ["uygulamasini", "uygulamasi", "programini"].contains(last) {
                    nameWords.removeLast()
                }
                guard (1...maxAppNameWords).contains(nameWords.count),
                      !nameWords.map(TurkishText.folded).contains(where: isNotAnAppWord) else { return nil }
                return make(nameWords.joined(separator: " "))
            }
        }
        return nil
    }

    private static let nonAppPrefixes = [
        "ses", "muzi", "sarki", "bilgisayar", "mac", "ekran", "bluetooth", "wifi", "wi", "internet", "odak",
        "odag", "rahatsiz", "mod", "karanlik", "aydinlik", "isik", "masaustu", "indirilen", "belge", "klasor", "dosya",
        "pencere", "zamanlayici", "alarm", "parlaklik", "bildirim", "kamera", "mikrofon", "ondan", "sonra", "ve", "ayar",
    ]

    private static func isNotAnAppWord(_ word: String) -> Bool {
        nonAppPrefixes.contains(where: word.hasPrefix) || word.contains("mod")
    }

    private static func leadingNumber(_ word: String) -> Int? {
        let digits = word.prefix(while: \.isNumber)
        return digits.isEmpty ? nil : Int(digits)
    }
}
