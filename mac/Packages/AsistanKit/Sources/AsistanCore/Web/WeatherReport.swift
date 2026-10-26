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

    /// `dayName` is "bugün", "yarın" or a weekday ("today", "tomorrow" or a weekday in English). A low rain
    /// chance is left out unless the question was about rain.
    public static func daily(city: String, dayName: String, minimum: Double, maximum: Double, code: Int,
                             rainChance: Int?, mentionRain: Bool = false, language: AssistantLanguage = .turkish) -> String {
        if language == .english {
            let sentence = "In \(city) \(dayName) it will be \(englishCondition(code: code)), \(englishRange(minimum, maximum))."
            return sentence + rainSentence(rainChance, mention: mentionRain, language: language)
        }
        let sentence = "\(TurkishGrammar.locative(city)) \(dayName) hava \(condition(code: code)), \(turkishRange(minimum, maximum))."
        return sentence + rainSentence(rainChance, mention: mentionRain, language: language)
    }

    /// The forecast for part of a day: "İzmir'de bugün akşam hava yağmurlu…".
    public static func partOfDay(city: String, dayName: String, part: WeatherQuestion.PartOfDay, window: HourlyWindow,
                                 mentionRain: Bool, language: AssistantLanguage = .turkish) -> String {
        if language == .english {
            let when = englishMoment(dayName: dayName, part: part)
            let sentence = "In \(city) \(when) it will be \(englishCondition(code: window.code)), \(englishRange(window.minimum, window.maximum))."
            return sentence + rainSentence(window.rainChance, mention: mentionRain, language: language)
        }
        let sentence = "\(TurkishGrammar.locative(city)) \(dayName) \(turkishName(part)) hava \(condition(code: window.code)), "
            + "\(turkishRange(window.minimum, window.maximum))."
        return sentence + rainSentence(window.rainChance, mention: mentionRain, language: language)
    }

    public struct HourlyWindow: Equatable, Sendable {
        public let minimum: Double
        public let maximum: Double
        /// The most severe weather in the window; WMO codes grow with severity.
        public let code: Int
        public let rainChance: Int?
    }

    /// Summarizes Open-Meteo's hourly arrays, which start at local midnight today, for `hours` of `dayOffset`.
    public static func window(hours: Range<Int>, dayOffset: Int, temperatures: [Double], codes: [Int],
                              rainChances: [Int?]) -> HourlyWindow? {
        let count = min(temperatures.count, codes.count, rainChances.count)
        let (lower, upper) = (dayOffset * 24 + hours.lowerBound, min(dayOffset * 24 + hours.upperBound, count))
        guard dayOffset >= 0, lower < upper else { return nil }
        let indices = lower..<upper
        guard let minimum = temperatures[indices].min(), let maximum = temperatures[indices].max(), let code = codes[indices].max()
        else { return nil }
        return HourlyWindow(minimum: minimum, maximum: maximum, code: code, rainChance: rainChances[indices].compactMap { $0 }.max())
    }

    private static func turkishRange(_ minimum: Double, _ maximum: Double) -> String {
        rounded(minimum) == rounded(maximum)
            ? "sıcaklık \(rounded(maximum)) derece"
            : "sıcaklık \(rounded(minimum)) ile \(rounded(maximum)) derece arasında"
    }

    private static func englishRange(_ minimum: Double, _ maximum: Double) -> String {
        rounded(minimum) == rounded(maximum)
            ? "\(rounded(maximum)) degrees"
            : "between \(rounded(minimum)) and \(rounded(maximum)) degrees"
    }

    private static func rainSentence(_ chance: Int?, mention: Bool, language: AssistantLanguage) -> String {
        guard let chance, mention || chance >= 30 else { return "" }
        return language == .english ? " There's a \(chance) percent chance of rain." : " Yağış ihtimali yüzde \(chance)."
    }

    private static func turkishName(_ part: WeatherQuestion.PartOfDay) -> String {
        switch part {
        case .morning: "sabah"
        case .noon: "öğlen"
        case .afternoon: "öğleden sonra"
        case .evening: "akşam"
        case .night: "gece"
        }
    }

    private static func englishMoment(dayName: String, part: WeatherQuestion.PartOfDay) -> String {
        let name = switch part {
        case .morning: "morning"
        case .noon: "around noon"
        case .afternoon: "afternoon"
        case .evening: "evening"
        case .night: "night"
        }
        guard dayName == "today" else { return "\(dayName) \(name)" }
        return switch part {
        case .noon: "today around noon"
        case .night: "tonight"
        default: "this \(name)"
        }
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
