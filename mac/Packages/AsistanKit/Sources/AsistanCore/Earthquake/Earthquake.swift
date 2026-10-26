import Foundation

public struct Earthquake: Sendable, Equatable, Identifiable {
    public let id: String
    public let date: Date
    public let magnitude: Double
    public let depthKm: Double
    public let location: GeoPoint
    /// As it is spoken: "Sındırgı, Balıkesir".
    public let place: String
    /// The province the source puts the event in, if any.
    public let province: String?

    public init(id: String, date: Date, magnitude: Double, depthKm: Double, location: GeoPoint, place: String,
                province: String?) {
        self.id = id
        self.date = date
        self.magnitude = magnitude
        self.depthKm = depthKm
        self.location = location
        self.place = place
        self.province = province
    }
}

public enum EarthquakeSource: String, Sendable {
    case afad, kandilli
}

public enum EarthquakeFeedError: Error, Equatable {
    case unreadable
}

/// AFAD's event service (servisnet.afad.gov.tr/apigateway/deprem/apiv2/event/filter): a JSON array whose
/// numbers come as strings, and whose dates are UTC without a zone.
public enum AFADEarthquakes {
    public static func parse(_ data: Data) throws -> [Earthquake] {
        guard let events = try? JSONSerialization.jsonObject(with: data) as? [[String: Any]] else {
            throw EarthquakeFeedError.unreadable
        }
        return events.compactMap(earthquake)
    }

    private static func earthquake(_ event: [String: Any]) -> Earthquake? {
        guard let id = text(event["eventID"]), let magnitude = number(event["magnitude"]),
              let latitude = number(event["latitude"]), let longitude = number(event["longitude"]),
              let date = text(event["date"]).flatMap(utcDate) else { return nil }
        let province = text(event["province"])
        let place = text(event["location"]).map(spokenPlace) ?? province ?? ""
        return Earthquake(id: "afad-\(id)", date: date, magnitude: magnitude, depthKm: number(event["depth"]) ?? 0,
                          location: GeoPoint(latitude: latitude, longitude: longitude), place: place, province: province)
    }

    /// "Ege Denizi - [10.82 km] Menderes (İzmir)" → "Ege Denizi, Menderes, İzmir".
    static func spokenPlace(_ location: String) -> String {
        location
            .replacingOccurrences(of: #"\[[^\]]*\]"#, with: "", options: .regularExpression)
            .replacingOccurrences(of: #"\s*\(([^)]*)\)"#, with: ", $1", options: .regularExpression)
            .replacingOccurrences(of: #"\s+-\s+"#, with: ", ", options: .regularExpression)
            .replacingOccurrences(of: #"\s{2,}"#, with: " ", options: .regularExpression)
            .replacingOccurrences(of: #"(,\s*)+"#, with: ", ", options: .regularExpression)
            .trimmingCharacters(in: CharacterSet(charactersIn: ", ").union(.whitespaces))
    }

    private static func utcDate(_ text: String) -> Date? {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = TimeZone(identifier: "UTC")
        formatter.dateFormat = "yyyy-MM-dd'T'HH:mm:ss"
        return formatter.date(from: String(text.prefix(19)))
    }

    private static func text(_ value: Any?) -> String? {
        switch value {
        case let string as String: string.trimmingCharacters(in: .whitespaces).isEmpty ? nil : string
        case let number as NSNumber: number.stringValue
        default: nil
        }
    }

    private static func number(_ value: Any?) -> Double? {
        switch value {
        case let number as NSNumber: number.doubleValue
        case let string as String: Double(string.trimmingCharacters(in: .whitespaces))
        default: nil
        }
    }
}

/// Kandilli Observatory's list (koeri.boun.edu.tr/scripts/lst0.asp): a fixed-width table inside <pre>,
/// in windows-1254, with Turkish local times and upper-case ASCII place names.
public enum KandilliEarthquakes {
    private static let row = try! NSRegularExpression(pattern:
        #"^(\d{4}\.\d{2}\.\d{2} \d{2}:\d{2}:\d{2})\s+(-?\d+\.\d+)\s+(-?\d+\.\d+)\s+(\d+(?:\.\d+)?)\s+(\S+)\s+(\S+)\s+(\S+)\s+(.+?)(?:\s{2,}.*)?$"#,
        options: .anchorsMatchLines)

    public static func text(from data: Data) -> String {
        String(data: data, encoding: .windowsCP1254) ?? String(decoding: data, as: UTF8.self)
    }

    public static func parse(_ text: String) -> [Earthquake] {
        let source = text.replacingOccurrences(of: "\r", with: "") as NSString
        return row.matches(in: source as String, range: NSRange(location: 0, length: source.length)).compactMap { match in
            let field = { (index: Int) in source.substring(with: match.range(at: index)) }
            // Moment magnitude is the most reliable for larger events; ML is the one usually given.
            guard let date = localDate(field(1)), let latitude = Double(field(2)), let longitude = Double(field(3)),
                  let magnitude = Double(field(7)) ?? Double(field(6)) ?? Double(field(5)) else { return nil }
            let (place, province) = spokenPlace(field(8).trimmingCharacters(in: .whitespaces))
            let stamp = field(1).filter(\.isNumber)
            return Earthquake(id: "kandilli-\(stamp)", date: date, magnitude: magnitude, depthKm: Double(field(4)) ?? 0,
                              location: GeoPoint(latitude: latitude, longitude: longitude), place: place, province: province)
        }
    }

    /// "KOZLU-SINDIRGI (BALIKESIR)" → ("Kozlu-Sindirgi, Balıkesir", "Balıkesir").
    static func spokenPlace(_ raw: String) -> (String, String?) {
        let titled = { (text: String) in text.lowercased(with: Locale(identifier: "en_US_POSIX")).capitalized }
        guard let open = raw.lastIndex(of: "("), let close = raw.lastIndex(of: ")"), open < close else {
            return (titled(raw), nil)
        }
        let area = String(raw[raw.index(after: open)..<close]).trimmingCharacters(in: .whitespaces)
        let local = String(raw[..<open]).trimmingCharacters(in: CharacterSet(charactersIn: " -"))
        let province = TurkishProvinces.find(area)?.name
        let region = province ?? titled(area)
        return (local.isEmpty ? region : "\(titled(local)), \(region)", province)
    }

    private static func localDate(_ text: String) -> Date? {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = TimeZone(identifier: "Europe/Istanbul")
        formatter.dateFormat = "yyyy.MM.dd HH:mm:ss"
        return formatter.date(from: text)
    }
}
