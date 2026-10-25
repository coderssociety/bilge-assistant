import Foundation

/// How long ago, as said: "12 dakika önce", "1 saat 20 dakika önce" / "12 minutes ago".
public enum SpokenAge {
    public static func text(since date: Date, now: Date, language: AssistantLanguage) -> String {
        let minutes = max(0, Int(now.timeIntervalSince(date) / 60))
        let (hours, days) = (minutes / 60, minutes / (24 * 60))
        if language == .english {
            if minutes < 1 { return "just now" }
            if minutes < 60 { return "\(minutes) \(minutes == 1 ? "minute" : "minutes") ago" }
            if days >= 1 { return "\(days) \(days == 1 ? "day" : "days") ago" }
            let rest = minutes % 60
            let hourText = "\(hours) \(hours == 1 ? "hour" : "hours")"
            return hours < 3 && rest > 0 ? "\(hourText) \(rest) \(rest == 1 ? "minute" : "minutes") ago" : "\(hourText) ago"
        }
        if minutes < 1 { return "az önce" }
        if minutes < 60 { return "\(minutes) dakika önce" }
        if days >= 1 { return "\(days) gün önce" }
        let rest = minutes % 60
        return hours < 3 && rest > 0 ? "\(hours) saat \(rest) dakika önce" : "\(hours) saat önce"
    }
}

/// Earthquake answers put into a few spoken sentences.
public struct EarthquakeReport: Sendable {
    /// Distance from a province centre that still counts as "İzmir ve çevresi".
    static let areaRadiusKm = 100.0
    /// Without a magnitude said, a country-wide list leaves out the many tremors nobody feels.
    static let feltMagnitude = 3.0
    private static let listedEvents = 3

    public struct Place: Sendable {
        public let name: String
        public let centre: GeoPoint

        public init(name: String, centre: GeoPoint) {
            self.name = name
            self.centre = centre
        }
    }

    public let query: EarthquakeQuery
    /// The user's city, for "yakınımda".
    public let home: Place?
    public let source: EarthquakeSource
    public let now: Date
    public let calendar: Calendar
    public let language: AssistantLanguage

    public init(query: EarthquakeQuery, home: Place?, source: EarthquakeSource, now: Date, calendar: Calendar = .current,
                language: AssistantLanguage) {
        self.query = query
        self.home = home
        self.source = source
        self.now = now
        self.calendar = calendar
        self.language = language
    }

    /// Where the question is about: a named province, the user's city, or nowhere in particular.
    var area: Place? {
        if let province = query.province { return Place(name: province.name, centre: province.centre) }
        return query.nearUser ? home : nil
    }

    public var window: DateInterval {
        let today = calendar.startOfDay(for: now)
        return switch query.period {
        case .lastDay: DateInterval(start: now.addingTimeInterval(-24 * 3600), end: now)
        case .today: DateInterval(start: today, end: now)
        case .yesterday: DateInterval(start: calendar.date(byAdding: .day, value: -1, to: today) ?? today, end: today)
        case .week: DateInterval(start: now.addingTimeInterval(-7 * 24 * 3600), end: now)
        }
    }

    public func text(for earthquakes: [Earthquake]) -> String {
        let inWindow = earthquakes.filter { window.contains($0.date) }
        let local = area.map { area in inWindow.filter { isNear($0, area) } } ?? inWindow
        let sentences: [String]
        if query.latestOnly {
            sentences = latest(local.filter { $0.magnitude >= (query.minimumMagnitude ?? 0) })
        } else {
            sentences = summary(local)
        }
        let credit = source == .kandilli
            ? (language == .english ? "Data from Kandilli Observatory." : "Bilgi Kandilli Rasathanesi'nden.") : nil
        return (sentences + [credit].compactMap { $0 }).joined(separator: " ")
    }

    private func isNear(_ quake: Earthquake, _ area: Place) -> Bool {
        if let province = quake.province, TurkishText.folded(province) == TurkishText.folded(area.name) { return true }
        return quake.location.kilometres(to: area.centre) <= Self.areaRadiusKm
    }

    private func latest(_ quakes: [Earthquake]) -> [String] {
        guard let quake = quakes.max(by: { $0.date < $1.date }) else { return [nothing(threshold: query.minimumMagnitude)] }
        let opening = language == .english ? "The latest earthquake" : "En son deprem"
        let areaNote = area.map { language == .english ? " in or near \($0.name)" : " \($0.name) ve çevresinde" } ?? ""
        return [language == .english
            ? "\(opening)\(areaNote) was \(describe(quake))"
            : "\(opening)\(areaNote): \(describe(quake))"]
    }

    private func summary(_ quakes: [Earthquake]) -> [String] {
        let threshold = query.minimumMagnitude ?? (area == nil ? Self.feltMagnitude : nil)
        let counted = quakes.filter { $0.magnitude >= (threshold ?? 0) }
        guard !counted.isEmpty else {
            guard let strongest = quakes.max(by: { $0.magnitude < $1.magnitude }) else { return [nothing(threshold: threshold)] }
            let lead = language == .english ? "The strongest was" : "En büyüğü:"
            return [nothing(threshold: threshold), "\(lead) \(describe(strongest))"]
        }
        let listed = counted.sorted { $0.magnitude > $1.magnitude }.prefix(Self.listedEvents).sorted { $0.date > $1.date }
        return [count(counted.count, threshold: threshold)] + listed.map { capitalizedFirst(describe($0)) }
    }

    /// "3 saat önce Sındırgı, Balıkesir merkezli 3,4 büyüklüğünde, derinlik 11 kilometre."
    func describe(_ quake: Earthquake) -> String {
        let age = SpokenAge.text(since: quake.date, now: now, language: language)
        let magnitude = Self.magnitude(quake.magnitude, language: language)
        let depth = max(0, Int(quake.depthKm.rounded()))
        let distance = area.map { area in (area.name, Int(quake.location.kilometres(to: area.centre).rounded())) }
        if language == .english {
            let away = distance.map { ", \($0.1) kilometers from \($0.0)" } ?? ""
            return "\(age), magnitude \(magnitude) near \(quake.place)\(away), \(depth) kilometers deep."
        }
        let away = distance.map { ", \($0.0) merkezine \($0.1) kilometre uzaklıkta" } ?? ""
        return "\(age) \(quake.place) merkezli \(magnitude) büyüklüğünde\(away), derinlik \(depth) kilometre."
    }

    private func count(_ count: Int, threshold: Double?) -> String {
        let scope = periodPhrase + areaPhrase
        if language == .english {
            let size = threshold.map { " of magnitude \(Self.threshold($0, language: language)) or more" } ?? ""
            let noun = count == 1 ? "was 1 earthquake" : "were \(count) earthquakes"
            return "\(scope) there \(noun)\(size)."
        }
        let size = threshold.map { " \(Self.threshold($0, language: language)) ve üzeri büyüklükte" } ?? ""
        return "\(scope)\(size) \(count) deprem oldu."
    }

    private func nothing(threshold: Double?) -> String {
        let scope = periodPhrase + areaPhrase
        if language == .english {
            let size = threshold.map { " of magnitude \(Self.threshold($0, language: language)) or more" } ?? ""
            return "\(scope) no earthquake\(size) was recorded."
        }
        let size = threshold.map { " \(Self.threshold($0, language: language)) ve üzeri büyüklükte" } ?? ""
        return "\(scope)\(size) deprem kaydedilmedi."
    }

    private var periodPhrase: String {
        switch (language, query.period) {
        case (.english, .lastDay): "In the last 24 hours"
        case (.english, .today): "Today"
        case (.english, .yesterday): "Yesterday"
        case (.english, .week): "In the past week"
        case (.turkish, .lastDay): "Son 24 saatte"
        case (.turkish, .today): "Bugün"
        case (.turkish, .yesterday): "Dün"
        case (.turkish, .week): "Son bir haftada"
        }
    }

    private var areaPhrase: String {
        guard let area else { return "" }
        return language == .english ? " in and around \(area.name)" : " \(area.name) ve çevresinde"
    }

    private func capitalizedFirst(_ text: String) -> String {
        text.prefix(1).uppercased(with: language.locale) + text.dropFirst()
    }

    static func magnitude(_ value: Double, language: AssistantLanguage) -> String {
        value.formatted(.number.precision(.fractionLength(1)).locale(language.locale))
    }

    /// "3 ve üzeri", but "4,5 ve üzeri".
    private static func threshold(_ value: Double, language: AssistantLanguage) -> String {
        value.formatted(.number.precision(.fractionLength(0...1)).locale(language.locale))
    }
}
