extension QuickIntent {
    public enum Window: Sendable, Equatable {
        case minimize, restore, close, fullScreen, exitFullScreen, leftHalf, rightHalf, maximize, hideOthers
    }
    public enum SystemInfoTopic: Sendable, Equatable { case disk, uptime, osVersion, network }
    public enum SettingsPane: String, Sendable, Equatable, CaseIterable {
        case wifi, bluetooth, network, sound, displays, battery, notifications, focus, privacy, keyboard,
             general, wallpaper, softwareUpdate, storage, accessibility, trackpad, mouse
    }
}

/// Fast-path rules for Mac controls added with the larger tool set. Same contract as the rest of
/// QuickIntentParser: exact, narrow phrasings only; everything else goes to the model.
enum MacQuickIntents {
    static func parse(_ w: [String]) -> QuickIntent? {
        screenshot(w) ?? wifi(w) ?? window(w) ?? settings(w) ?? systemInfo(w)
    }

    private static func screenshot(_ w: [String]) -> QuickIntent? {
        let phrases: Set<[String]> = [
            ["ekran", "goruntusu", "al"], ["ekran", "resmi", "al"], ["ekranin", "goruntusunu", "al"],
            ["ekran", "goruntusu", "cek"], ["ekranin", "resmini", "al"], ["ekran", "goruntusu"],
        ]
        return phrases.contains(w) ? .screenshot : nil
    }

    /// "Wi-Fi'ı" folds to "wi fii", so the words are compared without spaces.
    private static func wifi(_ w: [String]) -> QuickIntent? {
        let compact = w.joined().replacingOccurrences(of: " ", with: "")
        let subjects = ["wifi", "wifii", "wifiyi", "kablosuzu", "kablosuzagi"]
        for subject in subjects {
            if compact == subject + "ac" { return .wifi(on: true) }
            if compact == subject + "kapat" { return .wifi(on: false) }
        }
        return nil
    }

    private static func window(_ w: [String]) -> QuickIntent? {
        let body = w.first == "pencereyi" ? Array(w.dropFirst()) : w
        switch body {
        case ["kucult"], ["simge", "durumuna", "kucult"], ["dock", "a", "indir"]:
            return w.first == "pencereyi" ? .window(.minimize) : nil
        case ["geri", "getir"], ["eski", "haline", "getir"], ["eski", "boyutuna", "getir"], ["eski", "boyutuna", "dondur"]:
            return w.first == "pencereyi" ? .window(.restore) : nil
        case ["kapat"]:
            return w.first == "pencereyi" ? .window(.close) : nil
        case ["tam", "ekran", "yap"], ["tam", "ekrana", "al"], ["tam", "ekran"]:
            return .window(.fullScreen)
        case ["tam", "ekrandan", "cik"], ["tam", "ekrani", "kapat"], ["tam", "ekran", "modundan", "cik"]:
            return .window(.exitFullScreen)
        case ["sola", "al"], ["sola", "yasla"], ["ekranin", "soluna", "al"], ["sol", "yariya", "al"]:
            return w.first == "pencereyi" ? .window(.leftHalf) : nil
        case ["saga", "al"], ["saga", "yasla"], ["ekranin", "sagina", "al"], ["sag", "yariya", "al"]:
            return w.first == "pencereyi" ? .window(.rightHalf) : nil
        case ["buyut"], ["ekrani", "kaplasin"]:
            return w.first == "pencereyi" ? .window(.maximize) : nil
        case ["digerlerini", "gizle"], ["diger", "uygulamalari", "gizle"], ["digerlerini", "sakla"]:
            return .window(.hideOthers)
        default:
            return nil
        }
    }

    private static let paneWords: [(words: [String], pane: QuickIntent.SettingsPane)] = [
        (["wifi"], .wifi), (["wi", "fi"], .wifi), (["bluetooth"], .bluetooth), (["ag"], .network),
        (["ses"], .sound), (["ekran"], .displays), (["pil"], .battery), (["bildirim"], .notifications),
        (["odak"], .focus), (["gizlilik"], .privacy), (["guvenlik"], .privacy), (["klavye"], .keyboard),
        (["genel"], .general), (["duvar", "kagidi"], .wallpaper), (["yazilim", "guncelleme"], .softwareUpdate),
        (["depolama"], .storage), (["erisilebilirlik"], .accessibility), (["izleme", "dortgeni"], .trackpad),
        (["fare"], .mouse),
    ]

    /// "<bölüm> ayarlarını aç" / "<bölüm> ayarlarına git".
    private static func settings(_ w: [String]) -> QuickIntent? {
        let endings: [[String]] = [["ayarlarini", "ac"], ["ayarlarina", "git"], ["ayarlarini", "goster"]]
        guard let ending = endings.first(where: { w.count > $0.count && Array(w.suffix($0.count)) == $0 }) else { return nil }
        let subject = Array(w.dropLast(ending.count)).flatMap { $0.split(separator: " ").map(String.init) }
        return paneWords.first { $0.words == subject }.map { .settings($0.pane) }
    }

    private static func systemInfo(_ w: [String]) -> QuickIntent? {
        let disk: Set<[String]> = [
            ["diskte", "ne", "kadar", "yer", "var"], ["diskte", "ne", "kadar", "yer", "kaldi"], ["ne", "kadar", "bos", "yer", "var"],
            ["bos", "alan", "ne", "kadar"], ["disk", "doluluk", "orani"], ["ne", "kadar", "yer", "kaldi"],
        ]
        if disk.contains(w) { return .systemInfo(.disk) }
        let uptime: Set<[String]> = [
            ["bilgisayar", "ne", "zamandir", "acik"], ["mac", "ne", "zamandir", "acik"], ["ne", "zamandir", "aciksin"],
            ["bilgisayar", "kac", "gundur", "acik"],
        ]
        if uptime.contains(w) { return .systemInfo(.uptime) }
        let network: Set<[String]> = [
            ["ip", "adresim", "ne"], ["ip", "adresim", "kac"], ["yerel", "ip", "adresim", "ne"], ["hangi", "aga", "bagliyim"],
            ["hangi", "aga", "bagliyiz"], ["bagli", "oldugum", "ag", "ne"],
        ]
        if network.contains(w) { return .systemInfo(.network) }
        let os: Set<[String]> = [["macos", "surumu", "ne"], ["hangi", "macos", "surumu", "yuklu"], ["isletim", "sistemi", "surumu", "ne"]]
        return os.contains(w) ? .systemInfo(.osVersion) : nil
    }
}
