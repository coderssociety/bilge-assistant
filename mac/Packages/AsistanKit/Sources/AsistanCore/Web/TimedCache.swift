import Foundation

/// Answers kept for a while so repeated questions skip the network, and so an older answer can still be
/// given, with its age, when every source fails.
public struct TimedCache<Key: Hashable & Sendable, Value: Sendable>: Sendable {
    public let lifetime: TimeInterval
    private var entries: [Key: (value: Value, storedAt: Date)] = [:]

    public init(lifetime: TimeInterval) {
        self.lifetime = lifetime
    }

    public func fresh(_ key: Key, at now: Date) -> Value? {
        guard let entry = entries[key], now.timeIntervalSince(entry.storedAt) < lifetime else { return nil }
        return entry.value
    }

    /// Whatever is kept for `key`, however old.
    public func any(_ key: Key) -> (value: Value, storedAt: Date)? {
        entries[key]
    }

    public mutating func store(_ value: Value, for key: Key, at now: Date) {
        entries[key] = (value, now)
    }
}
