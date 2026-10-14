import Model

/// An in-memory cache of the answers to price, FX rate and index requests,
/// keyed by what was asked (the route or series and its dates), so
/// re-opening a check-in doesn't fetch again.
///
/// Concurrent requests for the same key share one fetch. Failures aren't
/// kept, so the next request tries again. Nothing is written to disk.
public actor PriceCache {
    private var entries: [String: Task<any Sendable, any Error>] = [:]

    public init() {}

    /// Whether a value for `key` is cached or being fetched.
    public func contains(_ key: String) -> Bool {
        entries[key] != nil
    }

    /// Forgets everything, so the next fetch asks the providers again.
    public func removeAll() {
        entries.removeAll()
    }

    /// The cached value for `key`, or the result of `fetch`, which is cached
    /// if it succeeds.
    func value<T: Sendable>(for key: String, fetch: @escaping @Sendable () async throws -> T) async throws -> T {
        let task: Task<any Sendable, any Error>
        if let existing = entries[key] {
            task = existing
        } else {
            task = Task { try await fetch() }
            entries[key] = task
        }
        do {
            guard let value = try await task.value as? T else {
                throw PriceFetchError.malformedResponse(service: "The price cache", detail: "a \(T.self) was expected")
            }
            return value
        } catch {
            if entries[key] == task { entries[key] = nil }
            throw error
        }
    }
}
