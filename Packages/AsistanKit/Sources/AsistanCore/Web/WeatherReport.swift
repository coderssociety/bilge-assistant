/// Turns Open-Meteo values into a short spoken Turkish sentence.
public enum WeatherReport {
    /// WMO weather interpretation codes, as Open-Meteo reports them.
    public static func condition(code: Int) -> String {
        switch code {
        case 0: "açık"
        case 1: "çoğunlukla açık"
        case 2: "parçalı bulutlu"
        case 3: "kapalı"
        case 45, 48: "sisli"
        case 51, 53, 55, 56, 57: "çiseleyen yağmurlu"
        case 61, 80: "hafif yağmurlu"
        case 63, 81: "yağmurlu"
        case 65, 82: "sağanak yağışlı"
        case 66, 67: "dondurucu yağmurlu"
        case 71, 85: "hafif karlı"
        case 73, 75, 77, 86: "karlı"
        case 95: "gök gürültülü fırtınalı"
        case 96, 99: "dolulu fırtınalı"
        default: "değişken"
        }
    }

    public static func current(city: String, temperature: Double, code: Int) -> String {
        "\(TurkishGrammar.locative(city)) şu an hava \(condition(code: code)), \(rounded(temperature)) derece."
    }

    /// `dayName` is "bugün", "yarın" or a weekday.
    public static func daily(city: String, dayName: String, minimum: Double, maximum: Double, code: Int,
                             rainChance: Int?) -> String {
        var sentence = "\(TurkishGrammar.locative(city)) \(dayName) hava \(condition(code: code)), sıcaklık \(rounded(minimum)) ile \(rounded(maximum)) derece arasında."
        if let rainChance, rainChance >= 30 { sentence += " Yağış ihtimali yüzde \(rainChance)." }
        return sentence
    }

    private static func rounded(_ value: Double) -> Int {
        Int(value.rounded())
    }
}
