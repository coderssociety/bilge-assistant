/// Which routines a spoken name means: "akşam rutini" (by the part of the day it runs in) or "hava durumu rutini"
/// (by its command).
public enum RoutineChoice {
    private static let parts: [String: RoutineSchedule.PartOfDay] = [
        "sabah": .morning, "sabahki": .morning, "morning": .morning,
        "ogle": .noon, "oglen": .noon, "ogleden": .noon, "ogleki": .noon, "noon": .noon, "afternoon": .noon,
        "aksam": .evening, "aksamki": .evening, "evening": .evening,
        "gece": .night, "geceki": .night, "night": .night,
    ]

    /// Those of `routines` the name fits, in their order; all of them for an empty name.
    public static func chosen(_ routines: [Routine], name: String) -> [Routine] {
        let words = TurkishText.folded(name).split(separator: " ").map(String.init)
        let named = Set(words.compactMap { parts[$0] })
        let rest = words.filter { parts[$0] == nil && $0 != "sonra" }.joined(separator: " ")
        let picked = routines.filter { named.isEmpty || named.contains(RoutineSchedule.partOfDay(hour: $0.hour)) }
        guard !rest.isEmpty else { return picked }
        return picked.filter { PhraseMatcher.matches(rest, title: $0.command) }
    }
}
