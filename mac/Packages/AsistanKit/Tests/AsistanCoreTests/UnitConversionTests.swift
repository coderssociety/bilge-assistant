import Testing
@testable import AsistanCore

@Suite("UnitConversion")
struct UnitConversionTests {
    @Test("answers Turkish conversions", arguments: [
        ("10 mil kaç kilometre", "10 mil 16,09 kilometre eder."),
        ("on mil kaç kilometre", "10 mil 16,09 kilometre eder."),
        ("100 fahrenheit kaç derece", "100 fahrenheit 37,78 santigrat derece eder."),
        ("30 derece kaç fahrenheit", "30 santigrat derece 86 fahrenheit eder."),
        ("2 litre kaç bardak", "2 litre 10 su bardağı eder."),
        ("iki litre su kaç su bardağı eder", "2 litre 10 su bardağı eder."),
        ("1 su bardağı kaç mililitre", "1 su bardağı 200 mililitre eder."),
        ("5 feet 10 inç kaç santim", "5 fit 10 inç 177,8 santimetre eder."),
        ("1 GB kaç MB", "1 gigabayt 1.024 megabayt eder."),
        ("60 mph kaç km/saat", "Saatte 60 mil saatte 96,56 kilometre eder."),
        ("1 dönüm kaç metrekare", "1 dönüm 1.000 metrekare eder."),
        ("bir dönüm kaç m²", "1 dönüm 1.000 metrekare eder."),
        ("5 ons kaç gram", "5 ons 141,75 gram eder."),
        ("10 kilo kaç libre", "10 kilogram 22,05 libre eder."),
        ("2,5 kg kaç pound", "2,5 kilogram 5,51 libre eder."),
        ("3 cup kaç ml", "3 cup 709,76 mililitre eder."),
        ("bir haftada kaç saat var", "1 hafta 168 saat eder."),
        ("1.500 metre kaç kilometre", "1.500 metre 1,5 kilometre eder."),
        ("10 kilometreyi mile çevir", "10 kilometre 6,21 mil eder."),
    ])
    func turkish(text: String, expected: String) throws {
        let conversion = try #require(UnitConversion.parse(text, language: .turkish))
        #expect(conversion.answer(language: .turkish) == expected)
    }

    @Test("answers English conversions", arguments: [
        ("how many kilometers is 10 miles", "10 miles is 16.09 kilometers."),
        ("convert 100 fahrenheit to celsius", "100 degrees Fahrenheit is 37.78 degrees Celsius."),
        ("5 feet 10 inches in cm", "5 feet 10 inches is 177.8 centimeters."),
        ("how many feet in a mile", "1 mile is 5,280 feet."),
        ("1 GB in MB", "1 gigabyte is 1,024 megabytes."),
        ("60 mph to km/h", "60 miles per hour is 96.56 kilometers per hour."),
        ("what's 2 pounds in kilograms", "2 pounds is 0.91 kilograms."),
        ("how many ml in 2 cups", "2 cups is 473.18 milliliters."),
    ])
    func english(text: String, expected: String) throws {
        let conversion = try #require(UnitConversion.parse(text, language: .english))
        #expect(conversion.answer(language: .english) == expected)
    }

    @Test("leaves other requests alone", arguments: [
        "50 dolar kaç lira", "dışarısı kaç derece", "Tokyo'da saat kaç", "saat kaç", "5 dakika sonra fırına bakmamı hatırlat",
        "3 saat sonra saat kaç olur", "10 km koşu kaç saat sürer", "yarın 30 derece olacak mı", "sesi yüzde 50 yap",
        "Maraton koşusu kaç kilometredir?", "2 kg un al", "48 bölü 6", "1 metre kaç metre",
    ])
    func notConversions(text: String) {
        #expect(UnitConversion.parse(text, language: .turkish) == nil)
    }

    @Test("leaves other English requests alone", arguments: [
        "convert 50 dollars to euros", "set a timer for 5 minutes", "remind me in 2 hours to call mom",
        "how cold is it outside", "add 2 kg flour to the list",
    ])
    func notEnglishConversions(text: String) {
        #expect(UnitConversion.parse(text, language: .english) == nil)
    }

    @Test("keeps decimals whole and splits number from unit", arguments: [
        ("2,5 kg", ["2,5", "kg"]), ("10km'ye", ["10", "kmye"]), ("1.5 liters", ["1.5", "liters"]), ("m² kaç", ["m2", "kac"]),
    ])
    func tokens(text: String, expected: [String]) {
        #expect(UnitConversion.tokenize(text) == expected)
    }
}
