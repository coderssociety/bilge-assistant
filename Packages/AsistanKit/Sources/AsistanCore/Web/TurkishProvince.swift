import Foundation

/// One of Turkey's 81 provinces with its licence-plate code, which the fuel price sources use as the
/// province id. Found in a command with its case endings: "İzmir'de", "Ankara'daki", "Konya için".
public struct TurkishProvince: Equatable, Sendable {
    public let name: String
    public let plate: Int

    public init(name: String, plate: Int) {
        self.name = name
        self.plate = plate
    }

    public static let all: [TurkishProvince] = [
        "Adana", "Adıyaman", "Afyonkarahisar", "Ağrı", "Amasya", "Ankara", "Antalya", "Artvin", "Aydın", "Balıkesir",
        "Bilecik", "Bingöl", "Bitlis", "Bolu", "Burdur", "Bursa", "Çanakkale", "Çankırı", "Çorum", "Denizli",
        "Diyarbakır", "Edirne", "Elazığ", "Erzincan", "Erzurum", "Eskişehir", "Gaziantep", "Giresun", "Gümüşhane", "Hakkari",
        "Hatay", "Isparta", "Mersin", "İstanbul", "İzmir", "Kars", "Kastamonu", "Kayseri", "Kırklareli", "Kırşehir",
        "Kocaeli", "Konya", "Kütahya", "Malatya", "Manisa", "Kahramanmaraş", "Mardin", "Muğla", "Muş", "Nevşehir",
        "Niğde", "Ordu", "Rize", "Sakarya", "Samsun", "Siirt", "Sinop", "Sivas", "Tekirdağ", "Tokat",
        "Trabzon", "Tunceli", "Şanlıurfa", "Uşak", "Van", "Yozgat", "Zonguldak", "Aksaray", "Bayburt", "Karaman",
        "Kırıkkale", "Batman", "Şırnak", "Bartın", "Ardahan", "Iğdır", "Yalova", "Karabük", "Kilis", "Osmaniye",
        "Düzce",
    ].enumerated().map { TurkishProvince(name: $0.element, plate: $0.offset + 1) }

    /// Names still in everyday use for a province or its centre.
    private static let aliases: [String: Int] = [
        "afyon": 3, "antep": 27, "icel": 33, "maras": 46, "urfa": 63, "izmit": 41, "adapazari": 54, "antakya": 31,
    ]
    /// Endings a province name takes in these requests, folded. The accusative is left out: "Kars'ı" would
    /// read "karşı" (against) as Kars.
    private static let endings: Set<String> = [
        "", "da", "de", "ta", "te", "daki", "deki", "taki", "teki", "dan", "den", "tan", "ten",
        "in", "nin", "un", "nun", "a", "e", "ya", "ye",
    ]
    /// Question particles that fold to Muş with the genitive ("biliyor musun"); only "Muş'un" written with ş
    /// is the province.
    static let questionParticles: Set<String> = ["musun", "müsün"]

    private static let byFoldedName: [String: TurkishProvince] = {
        var names = Dictionary(uniqueKeysWithValues: all.map { (TurkishText.folded($0.name), $0) })
        for (alias, plate) in aliases { names[alias] = all[plate - 1] }
        return names
    }()

    /// The first province named in `text`, with or without a case ending.
    public static func find(in text: String) -> TurkishProvince? {
        let words = zip(TurkishText.normalized(text).split(separator: " "), TurkishText.folded(text).split(separator: " "))
        for (spoken, word) in words where !questionParticles.contains(String(spoken)) {
            let word = String(word)
            for ending in endings where word.hasSuffix(ending) {
                if let province = byFoldedName[String(word.dropLast(ending.count))] { return province }
            }
        }
        return nil
    }

    /// The province a setting such as the default city names exactly ("izmir", "İzmir").
    public static func named(_ name: String) -> TurkishProvince? {
        byFoldedName[TurkishText.folded(name)]
    }
}

/// A place named in a request that is not necessarily a Turkish province: "Berlin'de", "in London".
public enum SpokenPlace {
    /// Words that take a locative ending in these requests without being places.
    private static let notPlaces: Set<String> = [
        "ramazan", "bayram", "kandil", "cuma", "bugun", "yarin", "aksam", "sabah", "ogle", "ikindi", "yatsi", "imsak",
        "iftar", "sahur", "turkiye", "pazartesi", "sali", "carsamba", "persembe", "cumartesi", "pazar",
        "ramadan", "today", "tomorrow", "monday", "tuesday", "wednesday", "thursday", "friday", "saturday", "sunday",
        "turkey",
    ]
    private static let turkishLocative = try! NSRegularExpression(pattern: #"(?<!\p{L})(\p{Lu}\p{L}+)['’](?:da|de|ta|te|daki|deki|taki|teki)(?!\p{L})"#)
    private static let englishIn = try! NSRegularExpression(pattern: #"(?<!\p{L})(?:[Ii]n|[Ff]or) (\p{Lu}\p{L}+(?: \p{Lu}\p{L}+)?)"#)

    public static func name(in text: String, language: AssistantLanguage) -> String? {
        let pattern = language == .english ? englishIn : turkishLocative
        let source = text as NSString
        for match in pattern.matches(in: text, range: NSRange(location: 0, length: source.length)) {
            let name = source.substring(with: match.range(at: 1))
            if !notPlaces.contains(TurkishText.folded(name)) { return name }
        }
        return nil
    }
}
