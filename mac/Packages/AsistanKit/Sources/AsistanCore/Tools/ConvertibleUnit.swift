import Foundation

/// Units the converter knows, with the words (folded, Turkish and English alike) that name them.
public enum ConvertibleUnit: String, CaseIterable, Sendable {
    case kilometer, meter, centimeter, millimeter, mile, yard, foot, inch, nauticalMile
    case kilogram, gram, milligram, metricTon, pound, ounce
    case liter, milliliter, glass, teaGlass, cup, gallon, tablespoon, teaspoon
    case celsius, fahrenheit, kelvin
    case kilometersPerHour, milesPerHour, metersPerSecond, knot
    case squareMeter, squareKilometer, squareFoot, hectare, donum, acre
    case byte, kilobyte, megabyte, gigabyte, terabyte
    case second, minute, hour, day, week

    public enum Kind: Sendable { case length, mass, volume, temperature, speed, area, data, duration }

    public var kind: Kind {
        switch self {
        case .kilometer, .meter, .centimeter, .millimeter, .mile, .yard, .foot, .inch, .nauticalMile: .length
        case .kilogram, .gram, .milligram, .metricTon, .pound, .ounce: .mass
        case .liter, .milliliter, .glass, .teaGlass, .cup, .gallon, .tablespoon, .teaspoon: .volume
        case .celsius, .fahrenheit, .kelvin: .temperature
        case .kilometersPerHour, .milesPerHour, .metersPerSecond, .knot: .speed
        case .squareMeter, .squareKilometer, .squareFoot, .hectare, .donum, .acre: .area
        case .byte, .kilobyte, .megabyte, .gigabyte, .terabyte: .data
        case .second, .minute, .hour, .day, .week: .duration
        }
    }

    /// Kitchen measures follow Turkish recipes: a "su bardağı" is 200 ml, a "çay bardağı" 100 ml, a
    /// spoon 15 or 5 ml; a cup is the US one (Foundation's is 240 ml). Data sizes count in 1024s, as file
    /// sizes are usually meant.
    var dimension: Dimension {
        switch self {
        case .kilometer: UnitLength.kilometers
        case .meter: UnitLength.meters
        case .centimeter: UnitLength.centimeters
        case .millimeter: UnitLength.millimeters
        case .mile: UnitLength.miles
        case .yard: UnitLength.yards
        case .foot: UnitLength.feet
        case .inch: UnitLength.inches
        case .nauticalMile: UnitLength.nauticalMiles
        case .kilogram: UnitMass.kilograms
        case .gram: UnitMass.grams
        case .milligram: UnitMass.milligrams
        case .metricTon: UnitMass.metricTons
        case .pound: UnitMass.pounds
        case .ounce: UnitMass.ounces
        case .liter: UnitVolume.liters
        case .milliliter: UnitVolume.milliliters
        case .glass: UnitVolume(symbol: "glass", converter: UnitConverterLinear(coefficient: 0.2))
        case .teaGlass: UnitVolume(symbol: "tea glass", converter: UnitConverterLinear(coefficient: 0.1))
        case .cup: UnitVolume(symbol: "cup", converter: UnitConverterLinear(coefficient: 0.236_588_236_5))
        case .gallon: UnitVolume.gallons
        case .tablespoon: UnitVolume(symbol: "tbsp", converter: UnitConverterLinear(coefficient: 0.015))
        case .teaspoon: UnitVolume(symbol: "tsp", converter: UnitConverterLinear(coefficient: 0.005))
        case .celsius: UnitTemperature.celsius
        case .fahrenheit: UnitTemperature.fahrenheit
        case .kelvin: UnitTemperature.kelvin
        case .kilometersPerHour: UnitSpeed.kilometersPerHour
        case .milesPerHour: UnitSpeed.milesPerHour
        case .metersPerSecond: UnitSpeed.metersPerSecond
        case .knot: UnitSpeed.knots
        case .squareMeter: UnitArea.squareMeters
        case .squareKilometer: UnitArea.squareKilometers
        case .squareFoot: UnitArea.squareFeet
        case .hectare: UnitArea.hectares
        case .donum: UnitArea(symbol: "dönüm", converter: UnitConverterLinear(coefficient: 1000))
        case .acre: UnitArea.acres
        case .byte: UnitInformationStorage.bytes
        case .kilobyte: UnitInformationStorage.kibibytes
        case .megabyte: UnitInformationStorage.mebibytes
        case .gigabyte: UnitInformationStorage.gibibytes
        case .terabyte: UnitInformationStorage.tebibytes
        case .second: UnitDuration.seconds
        case .minute: UnitDuration.minutes
        case .hour: UnitDuration.hours
        case .day: UnitDuration(symbol: "d", converter: UnitConverterLinear(coefficient: 86_400))
        case .week: UnitDuration(symbol: "w", converter: UnitConverterLinear(coefficient: 604_800))
        }
    }

    /// Folded words; several words are a phrase. Softened stems ("bardag") only match with an ending.
    var forms: [String] {
        switch self {
        case .kilometer: ["km", "kilometre", "kilometer", "kilometers", "kilometres"]
        case .meter: ["m", "metre", "meter", "meters", "metres"]
        case .centimeter: ["cm", "santim", "santimetre", "centimeter", "centimeters", "centimetre", "centimetres"]
        case .millimeter: ["mm", "milimetre", "millimeter", "millimeters", "millimetre", "millimetres"]
        case .mile: ["mil", "mile", "miles"]
        case .yard: ["yarda", "yard", "yards"]
        case .foot: ["fit", "feet", "foot", "ft"]
        case .inch: ["inc", "inch", "inches"]
        case .nauticalMile: ["deniz mili", "nautical mile", "nautical miles"]
        case .kilogram: ["kg", "kilo", "kilogram", "kilograms", "kilos"]
        case .gram: ["g", "gr", "gram", "grams"]
        case .milligram: ["mg", "miligram", "milligram", "milligrams"]
        case .metricTon: ["ton", "tons", "tonne", "tonnes"]
        case .pound: ["libre", "pound", "pounds", "lb", "lbs", "paund"]
        case .ounce: ["ons", "ounce", "ounces", "oz"]
        case .liter: ["l", "lt", "litre", "liter", "liters", "litres"]
        case .milliliter: ["ml", "mililitre", "milliliter", "milliliters", "millilitre", "millilitres", "cc"]
        case .glass: ["bardak", "bardag", "su bardag", "su bardagi", "glass", "glasses"]
        case .teaGlass: ["cay bardag", "cay bardagi", "tea glass", "tea glasses"]
        case .cup: ["cup", "cups"]
        case .gallon: ["galon", "gallon", "gallons"]
        case .tablespoon: ["yemek kasig", "yemek kasigi", "tablespoon", "tablespoons", "tbsp"]
        case .teaspoon: ["cay kasig", "cay kasigi", "teaspoon", "teaspoons", "tsp"]
        case .celsius: ["derece", "santigrat", "santigrat derece", "celsius", "degrees celsius", "degree celsius"]
        case .fahrenheit: ["fahrenheit", "fahrenhayt", "fahrenayt", "degrees fahrenheit", "degree fahrenheit"]
        case .kelvin: ["kelvin"]
        case .kilometersPerHour:
            ["km saat", "km sa", "km h", "kmh", "kph", "kilometre saat", "kilometers per hour", "kilometres per hour", "kilometer per hour"]
        case .milesPerHour: ["mph", "mil saat", "miles per hour", "mile per hour"]
        case .metersPerSecond: ["m s", "metre saniye", "meters per second", "metres per second", "meter per second"]
        case .knot: ["knot", "knots"]
        case .squareMeter:
            ["metrekare", "metre kare", "m2", "sqm", "square meter", "square meters", "square metre", "square metres"]
        case .squareKilometer:
            ["kilometrekare", "kilometre kare", "km2", "square kilometer", "square kilometers", "square kilometres"]
        case .squareFoot: ["fit kare", "square foot", "square feet", "sq ft", "sqft"]
        case .hectare: ["hektar", "hectare", "hectares"]
        case .donum: ["donum", "dekar", "dunam", "decare"]
        case .acre: ["akre", "acre", "acres"]
        case .byte: ["bayt", "byte", "bytes"]
        case .kilobyte: ["kb", "kilobayt", "kilobyte", "kilobytes"]
        case .megabyte: ["mb", "megabayt", "megabyte", "megabytes", "mega"]
        case .gigabyte: ["gb", "gigabayt", "gigabyte", "gigabytes", "giga", "gig"]
        case .terabyte: ["tb", "terabayt", "terabyte", "terabytes", "tera"]
        case .second: ["saniye", "sn", "second", "seconds", "sec"]
        case .minute: ["dakika", "dk", "minute", "minutes", "min"]
        case .hour: ["saat", "hour", "hours", "hr"]
        case .day: ["gun", "day", "days"]
        case .week: ["hafta", "week", "weeks"]
        }
    }

    /// Spoken after a number. Turkish nouns stay singular after numbers.
    func name(_ language: AssistantLanguage, plural: Bool) -> String {
        if language == .turkish { return turkishName }
        let (singular, many) = englishNames
        return plural ? many : singular
    }

    private var turkishName: String {
        switch self {
        case .kilometer: "kilometre"
        case .meter: "metre"
        case .centimeter: "santimetre"
        case .millimeter: "milimetre"
        case .mile: "mil"
        case .yard: "yarda"
        case .foot: "fit"
        case .inch: "inç"
        case .nauticalMile: "deniz mili"
        case .kilogram: "kilogram"
        case .gram: "gram"
        case .milligram: "miligram"
        case .metricTon: "ton"
        case .pound: "libre"
        case .ounce: "ons"
        case .liter: "litre"
        case .milliliter: "mililitre"
        case .glass: "su bardağı"
        case .teaGlass: "çay bardağı"
        case .cup: "cup"
        case .gallon: "galon"
        case .tablespoon: "yemek kaşığı"
        case .teaspoon: "çay kaşığı"
        case .celsius: "santigrat derece"
        case .fahrenheit: "fahrenheit"
        case .kelvin: "kelvin"
        case .kilometersPerHour: "kilometre"
        case .milesPerHour: "mil"
        case .metersPerSecond: "metre"
        case .knot: "knot"
        case .squareMeter: "metrekare"
        case .squareKilometer: "kilometrekare"
        case .squareFoot: "fit kare"
        case .hectare: "hektar"
        case .donum: "dönüm"
        case .acre: "akre"
        case .byte: "bayt"
        case .kilobyte: "kilobayt"
        case .megabyte: "megabayt"
        case .gigabyte: "gigabayt"
        case .terabyte: "terabayt"
        case .second: "saniye"
        case .minute: "dakika"
        case .hour: "saat"
        case .day: "gün"
        case .week: "hafta"
        }
    }

    private var englishNames: (String, String) {
        switch self {
        case .kilometer: ("kilometer", "kilometers")
        case .meter: ("meter", "meters")
        case .centimeter: ("centimeter", "centimeters")
        case .millimeter: ("millimeter", "millimeters")
        case .mile: ("mile", "miles")
        case .yard: ("yard", "yards")
        case .foot: ("foot", "feet")
        case .inch: ("inch", "inches")
        case .nauticalMile: ("nautical mile", "nautical miles")
        case .kilogram: ("kilogram", "kilograms")
        case .gram: ("gram", "grams")
        case .milligram: ("milligram", "milligrams")
        case .metricTon: ("metric ton", "metric tons")
        case .pound: ("pound", "pounds")
        case .ounce: ("ounce", "ounces")
        case .liter: ("liter", "liters")
        case .milliliter: ("milliliter", "milliliters")
        case .glass: ("glass", "glasses")
        case .teaGlass: ("tea glass", "tea glasses")
        case .cup: ("cup", "cups")
        case .gallon: ("gallon", "gallons")
        case .tablespoon: ("tablespoon", "tablespoons")
        case .teaspoon: ("teaspoon", "teaspoons")
        case .celsius: ("degree Celsius", "degrees Celsius")
        case .fahrenheit: ("degree Fahrenheit", "degrees Fahrenheit")
        case .kelvin: ("kelvin", "kelvins")
        case .kilometersPerHour: ("kilometer per hour", "kilometers per hour")
        case .milesPerHour: ("mile per hour", "miles per hour")
        case .metersPerSecond: ("meter per second", "meters per second")
        case .knot: ("knot", "knots")
        case .squareMeter: ("square meter", "square meters")
        case .squareKilometer: ("square kilometer", "square kilometers")
        case .squareFoot: ("square foot", "square feet")
        case .hectare: ("hectare", "hectares")
        case .donum: ("dönüm", "dönüms")
        case .acre: ("acre", "acres")
        case .byte: ("byte", "bytes")
        case .kilobyte: ("kilobyte", "kilobytes")
        case .megabyte: ("megabyte", "megabytes")
        case .gigabyte: ("gigabyte", "gigabytes")
        case .terabyte: ("terabyte", "terabytes")
        case .second: ("second", "seconds")
        case .minute: ("minute", "minutes")
        case .hour: ("hour", "hours")
        case .day: ("day", "days")
        case .week: ("week", "weeks")
        }
    }

    /// "60 mil" alone would not say it is a speed; Turkish puts the time first: "saatte 60 mil".
    func spoken(_ number: String, value: Double, language: AssistantLanguage) -> String {
        let phrase = "\(number) \(name(language, plural: value != 1))"
        guard language == .turkish else { return phrase }
        switch self {
        case .kilometersPerHour, .milesPerHour: return "saatte \(phrase)"
        case .metersPerSecond: return "saniyede \(phrase)"
        default: return phrase
        }
    }
}
