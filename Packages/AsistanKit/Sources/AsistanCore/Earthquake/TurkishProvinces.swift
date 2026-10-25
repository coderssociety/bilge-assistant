import Foundation

public struct GeoPoint: Sendable, Equatable {
    private static let earthRadiusKm = 6371.0

    public let latitude: Double
    public let longitude: Double

    public init(latitude: Double, longitude: Double) {
        self.latitude = latitude
        self.longitude = longitude
    }

    /// Great-circle (haversine) distance.
    public func kilometres(to other: GeoPoint) -> Double {
        let radians = Double.pi / 180
        let (from, to) = (latitude * radians, other.latitude * radians)
        let latitudeDelta = to - from
        let longitudeDelta = (other.longitude - longitude) * radians
        let a = pow(sin(latitudeDelta / 2), 2) + cos(from) * cos(to) * pow(sin(longitudeDelta / 2), 2)
        return 2 * Self.earthRadiusKm * asin(min(1, sqrt(a)))
    }
}

public struct Province: Sendable, Equatable {
    public let name: String
    public let centre: GeoPoint
    /// Folded; other names people use for the province or its centre ("Antep", "İzmit").
    let aliases: [String]

    init(_ name: String, _ latitude: Double, _ longitude: Double, aliases: [String] = []) {
        self.name = name
        centre = GeoPoint(latitude: latitude, longitude: longitude)
        self.aliases = aliases
    }

    var keys: [String] { [TurkishText.folded(name)] + aliases }
}

/// The 81 province centres, for "İzmir'de deprem var mı" and distances from the user's city.
public enum TurkishProvinces {
    /// Case endings a province name takes in a request: "İzmir'de", "Van'da", "Bolu'nun".
    private static let endings: Set<String> = [
        "", "da", "de", "ta", "te", "dan", "den", "tan", "ten", "in", "nin", "un", "nun", "a", "e", "ya", "ye",
        "i", "yi", "u", "yu", "daki", "deki", "taki", "teki", "civari", "civarinda",
    ]

    public static let all: [Province] = [
        Province("Adana", 37.00, 35.32), Province("Adıyaman", 37.76, 38.28),
        Province("Afyonkarahisar", 38.76, 30.54, aliases: ["afyon"]), Province("Ağrı", 39.72, 43.05),
        Province("Amasya", 40.65, 35.83), Province("Ankara", 39.93, 32.86), Province("Antalya", 36.89, 30.71),
        Province("Artvin", 41.18, 41.82), Province("Aydın", 37.85, 27.85), Province("Balıkesir", 39.65, 27.88),
        Province("Bilecik", 40.14, 29.98), Province("Bingöl", 38.88, 40.50), Province("Bitlis", 38.40, 42.11),
        Province("Bolu", 40.74, 31.61), Province("Burdur", 37.72, 30.29), Province("Bursa", 40.19, 29.06),
        Province("Çanakkale", 40.15, 26.41), Province("Çankırı", 40.60, 33.62), Province("Çorum", 40.55, 34.95),
        Province("Denizli", 37.78, 29.09), Province("Diyarbakır", 37.91, 40.23), Province("Edirne", 41.68, 26.56),
        Province("Elazığ", 38.67, 39.22), Province("Erzincan", 39.75, 39.49), Province("Erzurum", 39.90, 41.27),
        Province("Eskişehir", 39.78, 30.52), Province("Gaziantep", 37.07, 37.38, aliases: ["antep"]),
        Province("Giresun", 40.91, 38.39), Province("Gümüşhane", 40.46, 39.48), Province("Hakkari", 37.58, 43.74),
        Province("Hatay", 36.20, 36.16, aliases: ["antakya"]), Province("Isparta", 37.76, 30.55),
        Province("Mersin", 36.81, 34.64, aliases: ["icel"]), Province("İstanbul", 41.01, 28.98),
        Province("İzmir", 38.42, 27.14), Province("Kars", 40.60, 43.10), Province("Kastamonu", 41.38, 33.78),
        Province("Kayseri", 38.73, 35.49), Province("Kırklareli", 41.73, 27.22), Province("Kırşehir", 39.15, 34.16),
        Province("Kocaeli", 40.77, 29.92, aliases: ["izmit"]), Province("Konya", 37.87, 32.48),
        Province("Kütahya", 39.42, 29.98), Province("Malatya", 38.35, 38.31), Province("Manisa", 38.61, 27.43),
        Province("Kahramanmaraş", 37.58, 36.94, aliases: ["maras"]), Province("Mardin", 37.31, 40.74),
        Province("Muğla", 37.22, 28.36), Province("Muş", 38.75, 41.51), Province("Nevşehir", 38.62, 34.71),
        Province("Niğde", 37.97, 34.68), Province("Ordu", 40.98, 37.88), Province("Rize", 41.02, 40.52),
        Province("Sakarya", 40.78, 30.40, aliases: ["adapazari"]), Province("Samsun", 41.29, 36.33),
        Province("Siirt", 37.93, 41.94), Province("Sinop", 42.03, 35.15), Province("Sivas", 39.75, 37.02),
        Province("Tekirdağ", 40.98, 27.51), Province("Tokat", 40.31, 36.55), Province("Trabzon", 41.00, 39.72),
        Province("Tunceli", 39.11, 39.55), Province("Şanlıurfa", 37.16, 38.79, aliases: ["urfa"]),
        Province("Uşak", 38.68, 29.41), Province("Van", 38.50, 43.38), Province("Yozgat", 39.82, 34.81),
        Province("Zonguldak", 41.45, 31.79), Province("Aksaray", 38.37, 34.03), Province("Bayburt", 40.26, 40.23),
        Province("Karaman", 37.18, 33.22), Province("Kırıkkale", 39.85, 33.51), Province("Batman", 37.88, 41.13),
        Province("Şırnak", 37.52, 42.46), Province("Bartın", 41.63, 32.34), Province("Ardahan", 41.11, 42.70),
        Province("Iğdır", 39.92, 44.05), Province("Yalova", 40.65, 29.27), Province("Karabük", 41.20, 32.62),
        Province("Kilis", 36.72, 37.12), Province("Osmaniye", 37.07, 36.25), Province("Düzce", 40.84, 31.16),
    ]

    /// The province a name stands for, as typed in Settings or given by a data source ("BALIKESIR").
    public static func find(_ name: String) -> Province? {
        let folded = TurkishText.folded(name)
        return all.first { $0.keys.contains(folded) }
    }

    /// The province named in a request; the longest matching name wins.
    public static func named(in text: String) -> Province? {
        let words = TurkishText.folded(text).split(separator: " ").map(String.init)
        var best: (province: Province, length: Int)?
        for province in all {
            for key in province.keys where key.count > (best?.length ?? 0) {
                let matches = words.contains { word in
                    word.hasPrefix(key) && endings.contains(String(word.dropFirst(key.count)))
                }
                if matches { best = (province, key.count) }
            }
        }
        return best?.province
    }
}
