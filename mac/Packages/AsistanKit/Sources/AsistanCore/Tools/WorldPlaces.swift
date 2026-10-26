import Foundation

/// A city or country and its time zone; a country is answered with its capital's or largest city's zone.
public struct WorldPlace: Equatable, Sendable {
    public let turkishName: String
    public let englishName: String
    public let timeZoneIdentifier: String
    /// Folded names, Turkish and English, that refer to it.
    let names: [String]

    init(_ turkishName: String, _ englishName: String, _ timeZoneIdentifier: String, aliases: [String] = []) {
        self.turkishName = turkishName
        self.englishName = englishName
        self.timeZoneIdentifier = timeZoneIdentifier
        names = Array(Set([turkishName, englishName].map(TurkishText.folded) + aliases))
    }

    public func name(_ language: AssistantLanguage) -> String {
        language == .turkish ? turkishName : englishName
    }

    static let all: [WorldPlace] = cities + countries

    private static let cities: [WorldPlace] = [
        .init("İstanbul", "Istanbul", "Europe/Istanbul"), .init("Ankara", "Ankara", "Europe/Istanbul"),
        .init("İzmir", "Izmir", "Europe/Istanbul"), .init("Lefkoşa", "Nicosia", "Asia/Nicosia"),
        .init("Londra", "London", "Europe/London"), .init("Dublin", "Dublin", "Europe/Dublin"),
        .init("Lizbon", "Lisbon", "Europe/Lisbon"), .init("Madrid", "Madrid", "Europe/Madrid"),
        .init("Barselona", "Barcelona", "Europe/Madrid"), .init("Paris", "Paris", "Europe/Paris"),
        .init("Brüksel", "Brussels", "Europe/Brussels"), .init("Amsterdam", "Amsterdam", "Europe/Amsterdam"),
        .init("Berlin", "Berlin", "Europe/Berlin"), .init("Münih", "Munich", "Europe/Berlin"),
        .init("Frankfurt", "Frankfurt", "Europe/Berlin"), .init("Hamburg", "Hamburg", "Europe/Berlin"),
        .init("Köln", "Cologne", "Europe/Berlin"), .init("Zürih", "Zurich", "Europe/Zurich"),
        .init("Cenevre", "Geneva", "Europe/Zurich"), .init("Viyana", "Vienna", "Europe/Vienna"),
        .init("Roma", "Rome", "Europe/Rome"), .init("Milano", "Milan", "Europe/Rome"),
        .init("Prag", "Prague", "Europe/Prague"), .init("Varşova", "Warsaw", "Europe/Warsaw"),
        .init("Budapeşte", "Budapest", "Europe/Budapest"), .init("Kopenhag", "Copenhagen", "Europe/Copenhagen"),
        .init("Stockholm", "Stockholm", "Europe/Stockholm"), .init("Oslo", "Oslo", "Europe/Oslo"),
        .init("Helsinki", "Helsinki", "Europe/Helsinki"), .init("Atina", "Athens", "Europe/Athens"),
        .init("Sofya", "Sofia", "Europe/Sofia"), .init("Bükreş", "Bucharest", "Europe/Bucharest"),
        .init("Belgrad", "Belgrade", "Europe/Belgrade"), .init("Saraybosna", "Sarajevo", "Europe/Sarajevo"),
        .init("Üsküp", "Skopje", "Europe/Skopje"), .init("Kiev", "Kyiv", "Europe/Kyiv", aliases: ["kyiv"]),
        .init("Moskova", "Moscow", "Europe/Moscow"), .init("Bakü", "Baku", "Asia/Baku"),
        .init("Tiflis", "Tbilisi", "Asia/Tbilisi"), .init("Erivan", "Yerevan", "Asia/Yerevan"),
        .init("Tahran", "Tehran", "Asia/Tehran"), .init("Bağdat", "Baghdad", "Asia/Baghdad"),
        .init("Şam", "Damascus", "Asia/Damascus"), .init("Beyrut", "Beirut", "Asia/Beirut"),
        .init("Amman", "Amman", "Asia/Amman"), .init("Kudüs", "Jerusalem", "Asia/Jerusalem"),
        .init("Tel Aviv", "Tel Aviv", "Asia/Jerusalem"), .init("Kahire", "Cairo", "Africa/Cairo"),
        .init("Riyad", "Riyadh", "Asia/Riyadh"), .init("Mekke", "Mecca", "Asia/Riyadh", aliases: ["makkah"]),
        .init("Medine", "Medina", "Asia/Riyadh"), .init("Cidde", "Jeddah", "Asia/Riyadh"),
        .init("Doha", "Doha", "Asia/Qatar"), .init("Dubai", "Dubai", "Asia/Dubai", aliases: ["dubay"]),
        .init("Abu Dabi", "Abu Dhabi", "Asia/Dubai"), .init("Kuveyt", "Kuwait", "Asia/Kuwait"),
        .init("Taşkent", "Tashkent", "Asia/Tashkent"), .init("Almatı", "Almaty", "Asia/Almaty"),
        .init("Astana", "Astana", "Asia/Almaty"), .init("Bişkek", "Bishkek", "Asia/Bishkek"),
        .init("Aşkabat", "Ashgabat", "Asia/Ashgabat"), .init("Kabil", "Kabul", "Asia/Kabul"),
        .init("Karaçi", "Karachi", "Asia/Karachi"), .init("İslamabad", "Islamabad", "Asia/Karachi"),
        .init("Yeni Delhi", "New Delhi", "Asia/Kolkata", aliases: ["delhi"]),
        .init("Mumbai", "Mumbai", "Asia/Kolkata", aliases: ["bombay"]), .init("Katmandu", "Kathmandu", "Asia/Kathmandu"),
        .init("Dakka", "Dhaka", "Asia/Dhaka"), .init("Bangkok", "Bangkok", "Asia/Bangkok"),
        .init("Singapur", "Singapore", "Asia/Singapore"), .init("Kuala Lumpur", "Kuala Lumpur", "Asia/Kuala_Lumpur"),
        .init("Cakarta", "Jakarta", "Asia/Jakarta"), .init("Bali", "Bali", "Asia/Makassar"),
        .init("Manila", "Manila", "Asia/Manila"), .init("Hong Kong", "Hong Kong", "Asia/Hong_Kong"),
        .init("Pekin", "Beijing", "Asia/Shanghai", aliases: ["peking"]), .init("Şanghay", "Shanghai", "Asia/Shanghai"),
        .init("Taipei", "Taipei", "Asia/Taipei"), .init("Seul", "Seoul", "Asia/Seoul"),
        .init("Tokyo", "Tokyo", "Asia/Tokyo"), .init("Osaka", "Osaka", "Asia/Tokyo"),
        .init("Sidney", "Sydney", "Australia/Sydney"), .init("Melbourne", "Melbourne", "Australia/Melbourne"),
        .init("Perth", "Perth", "Australia/Perth"), .init("Auckland", "Auckland", "Pacific/Auckland"),
        .init("Honolulu", "Honolulu", "Pacific/Honolulu"), .init("Los Angeles", "Los Angeles", "America/Los_Angeles"),
        .init("San Francisco", "San Francisco", "America/Los_Angeles"), .init("Seattle", "Seattle", "America/Los_Angeles"),
        .init("Las Vegas", "Las Vegas", "America/Los_Angeles"), .init("Vancouver", "Vancouver", "America/Vancouver"),
        .init("Denver", "Denver", "America/Denver"), .init("Şikago", "Chicago", "America/Chicago"),
        .init("Dallas", "Dallas", "America/Chicago"), .init("Houston", "Houston", "America/Chicago"),
        .init("Meksiko", "Mexico City", "America/Mexico_City"), .init("New York", "New York", "America/New_York"),
        .init("Washington", "Washington", "America/New_York", aliases: ["vasington"]),
        .init("Boston", "Boston", "America/New_York"), .init("Miami", "Miami", "America/New_York"),
        .init("Toronto", "Toronto", "America/Toronto"), .init("Montreal", "Montreal", "America/Toronto"),
        .init("Bogota", "Bogota", "America/Bogota"), .init("Lima", "Lima", "America/Lima"),
        .init("Santiago", "Santiago", "America/Santiago"), .init("Buenos Aires", "Buenos Aires", "America/Argentina/Buenos_Aires"),
        .init("São Paulo", "São Paulo", "America/Sao_Paulo", aliases: ["sao paulo"]),
        .init("Rio de Janeiro", "Rio de Janeiro", "America/Sao_Paulo"), .init("Kazablanka", "Casablanca", "Africa/Casablanca"),
        .init("Cezayir", "Algiers", "Africa/Algiers"), .init("Tunus", "Tunis", "Africa/Tunis"),
        .init("Lagos", "Lagos", "Africa/Lagos"), .init("Nairobi", "Nairobi", "Africa/Nairobi"),
        .init("Addis Ababa", "Addis Ababa", "Africa/Addis_Ababa"), .init("Johannesburg", "Johannesburg", "Africa/Johannesburg"),
        .init("Cape Town", "Cape Town", "Africa/Johannesburg"), .init("Reykjavik", "Reykjavik", "Atlantic/Reykjavik"),
    ]

    private static let countries: [WorldPlace] = [
        .init("Türkiye", "Turkey", "Europe/Istanbul", aliases: ["turkiye"]),
        .init("Kıbrıs", "Cyprus", "Asia/Nicosia", aliases: ["kktc"]),
        .init("İngiltere", "England", "Europe/London", aliases: ["birlesik krallik", "united kingdom", "uk", "britain"]),
        .init("İrlanda", "Ireland", "Europe/Dublin"), .init("Portekiz", "Portugal", "Europe/Lisbon"),
        .init("İspanya", "Spain", "Europe/Madrid"), .init("Fransa", "France", "Europe/Paris"),
        .init("Belçika", "Belgium", "Europe/Brussels"), .init("Hollanda", "the Netherlands", "Europe/Amsterdam", aliases: ["netherlands"]),
        .init("Almanya", "Germany", "Europe/Berlin"), .init("İsviçre", "Switzerland", "Europe/Zurich"),
        .init("Avusturya", "Austria", "Europe/Vienna"), .init("İtalya", "Italy", "Europe/Rome"),
        .init("Çekya", "Czechia", "Europe/Prague", aliases: ["cek cumhuriyeti", "czech republic"]),
        .init("Polonya", "Poland", "Europe/Warsaw"), .init("Macaristan", "Hungary", "Europe/Budapest"),
        .init("Danimarka", "Denmark", "Europe/Copenhagen"), .init("İsveç", "Sweden", "Europe/Stockholm"),
        .init("Norveç", "Norway", "Europe/Oslo"), .init("Finlandiya", "Finland", "Europe/Helsinki"),
        .init("Yunanistan", "Greece", "Europe/Athens"), .init("Bulgaristan", "Bulgaria", "Europe/Sofia"),
        .init("Romanya", "Romania", "Europe/Bucharest"), .init("Sırbistan", "Serbia", "Europe/Belgrade"),
        .init("Bosna", "Bosnia", "Europe/Sarajevo"), .init("Ukrayna", "Ukraine", "Europe/Kyiv"),
        .init("Rusya", "Russia", "Europe/Moscow"), .init("Azerbaycan", "Azerbaijan", "Asia/Baku"),
        .init("Gürcistan", "Georgia", "Asia/Tbilisi"), .init("Ermenistan", "Armenia", "Asia/Yerevan"),
        .init("İran", "Iran", "Asia/Tehran"), .init("Irak", "Iraq", "Asia/Baghdad"),
        .init("Suriye", "Syria", "Asia/Damascus"), .init("Lübnan", "Lebanon", "Asia/Beirut"),
        .init("Ürdün", "Jordan", "Asia/Amman"), .init("İsrail", "Israel", "Asia/Jerusalem"),
        .init("Mısır", "Egypt", "Africa/Cairo"), .init("Suudi Arabistan", "Saudi Arabia", "Asia/Riyadh"),
        .init("Katar", "Qatar", "Asia/Qatar"),
        .init("Birleşik Arap Emirlikleri", "the United Arab Emirates", "Asia/Dubai", aliases: ["bae", "emirlikler", "uae"]),
        .init("Özbekistan", "Uzbekistan", "Asia/Tashkent"), .init("Kazakistan", "Kazakhstan", "Asia/Almaty"),
        .init("Kırgızistan", "Kyrgyzstan", "Asia/Bishkek"), .init("Türkmenistan", "Turkmenistan", "Asia/Ashgabat"),
        .init("Afganistan", "Afghanistan", "Asia/Kabul"), .init("Pakistan", "Pakistan", "Asia/Karachi"),
        .init("Hindistan", "India", "Asia/Kolkata"), .init("Bangladeş", "Bangladesh", "Asia/Dhaka"),
        .init("Tayland", "Thailand", "Asia/Bangkok"), .init("Malezya", "Malaysia", "Asia/Kuala_Lumpur"),
        .init("Endonezya", "Indonesia", "Asia/Jakarta"), .init("Filipinler", "the Philippines", "Asia/Manila", aliases: ["philippines"]),
        .init("Çin", "China", "Asia/Shanghai"), .init("Tayvan", "Taiwan", "Asia/Taipei"),
        .init("Güney Kore", "South Korea", "Asia/Seoul", aliases: ["kore", "korea"]), .init("Japonya", "Japan", "Asia/Tokyo"),
        .init("Avustralya", "Australia", "Australia/Sydney"), .init("Yeni Zelanda", "New Zealand", "Pacific/Auckland"),
        .init("Amerika", "America", "America/New_York", aliases: ["abd", "amerika birlesik devletleri", "usa", "united states"]),
        .init("Kanada", "Canada", "America/Toronto"), .init("Meksika", "Mexico", "America/Mexico_City"),
        .init("Kolombiya", "Colombia", "America/Bogota"), .init("Peru", "Peru", "America/Lima"),
        .init("Şili", "Chile", "America/Santiago"), .init("Arjantin", "Argentina", "America/Argentina/Buenos_Aires"),
        .init("Brezilya", "Brazil", "America/Sao_Paulo"), .init("Fas", "Morocco", "Africa/Casablanca"),
        .init("Cezayir", "Algeria", "Africa/Algiers"), .init("Nijerya", "Nigeria", "Africa/Lagos"),
        .init("Kenya", "Kenya", "Africa/Nairobi"), .init("Etiyopya", "Ethiopia", "Africa/Addis_Ababa"),
        .init("Güney Afrika", "South Africa", "Africa/Johannesburg"), .init("İzlanda", "Iceland", "Atlantic/Reykjavik"),
    ]
}
