/// Turns Open-Meteo values into a short spoken sentence in the assistant's language.
public enum WeatherReport {
    /// WMO weather interpretation codes, as Open-Meteo reports them.
    public static func condition(code: Int, language: AssistantLanguage = .turkish) -> String {
        if language == .english { return englishCondition(code: code) }
        return switch code {
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

    public static func current(city: String, temperature: Double, code: Int, language: AssistantLanguage = .turkish) -> String {
        if language == .english {
            return "In \(city) it's \(englishCondition(code: code)) right now, \(rounded(temperature)) degrees."
        }
        return "\(TurkishGrammar.locative(city)) şu an hava \(condition(code: code)), \(rounded(temperature)) derece."
    }

    /// `dayName` is "bugün", "yarın" or a weekday ("today", "tomorrow" or a weekday in English).
    public static func daily(city: String, dayName: String, minimum: Double, maximum: Double, code: Int,
                             rainChance: Int?, language: AssistantLanguage = .turkish) -> String {
        if language == .english {
            var sentence = "In \(city) \(dayName) it will be \(englishCondition(code: code)), between \(rounded(minimum)) and \(rounded(maximum)) degrees."
            if let rainChance, rainChance >= 30 { sentence += " There's a \(rainChance) percent chance of rain." }
            return sentence
        }
        var sentence = "\(TurkishGrammar.locative(city)) \(dayName) hava \(condition(code: code)), sıcaklık \(rounded(minimum)) ile \(rounded(maximum)) derece arasında."
        if let rainChance, rainChance >= 30 { sentence += " Yağış ihtimali yüzde \(rainChance)." }
        return sentence
    }

    private static func englishCondition(code: Int) -> String {
        switch code {
        case 0: "clear"
        case 1: "mostly clear"
        case 2: "partly cloudy"
        case 3: "overcast"
        case 45, 48: "foggy"
        case 51, 53, 55, 56, 57: "drizzly"
        case 61, 80: "lightly rainy"
        case 63, 81: "rainy"
        case 65, 82: "pouring"
        case 66, 67: "freezing rain"
        case 71, 85: "lightly snowy"
        case 73, 75, 77, 86: "snowy"
        case 95: "stormy with thunder"
        case 96, 99: "stormy with hail"
        default: "changeable"
        }
    }

    private static func rounded(_ value: Double) -> Int {
        Int(value.rounded())
    }
}
