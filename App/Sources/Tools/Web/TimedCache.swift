import AsistanCore
import Foundation
import Synchronization

/// Fetched data kept for a while. When a later fetch fails, the last value is still given, marked stale,
/// so the answer can say how old it is instead of failing outright.
final class TimedCache<Value: Sendable>: Sendable {
    struct Entry: Sendable {
        let value: Value
        let fetched: Date
        let isStale: Bool

        /// "Güncel bilgiye ulaşamadım; 12 dakika önce alınan bilgiye göre: " for a stale value, otherwise empty.
        var stalenessNote: String {
            guard isStale else { return "" }
            let age = SpokenAge.text(since: fetched, now: .now, language: AppLanguage.current)
            return String(localized: "Güncel bilgiye ulaşamadım; \(age) alınan bilgiye göre: ")
        }
    }

    private let entries = Mutex<[String: Entry]>([:])
    private let staleLimit: TimeInterval

    init(staleLimit: TimeInterval = 6 * 60 * 60) {
        self.staleLimit = staleLimit
    }

    func value(for key: String, maxAge: TimeInterval, fetch: () async throws -> Value) async throws -> Entry {
        let cached = entries.withLock { $0[key] }
        if let cached, Date.now.timeIntervalSince(cached.fetched) < maxAge { return cached }
        do {
            let entry = Entry(value: try await fetch(), fetched: .now, isStale: false)
            entries.withLock { $0[key] = entry }
            return entry
        } catch is CancellationError {
            throw CancellationError()
        } catch {
            guard let cached, Date.now.timeIntervalSince(cached.fetched) < staleLimit else { throw error }
            Log.tools.error("Fetch failed, using cached \(key, privacy: .public): \(error.localizedDescription, privacy: .public)")
            return Entry(value: cached.value, fetched: cached.fetched, isStale: true)
        }
    }
}
