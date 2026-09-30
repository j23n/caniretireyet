import Model

/// An in-memory cache of fetched quotes, FX rates and index values, keyed by
/// provider, symbol and check-in date, so re-opening a check-in doesn't fetch
/// again.
///
/// Concurrent requests for the same key share one fetch. Failures aren't
/// kept, so the next request tries again. Nothing is written to disk.
public actor PriceCache {
    /// What a cached value is for.
    public struct Key: Hashable, Sendable {
        /// The provider, e.g. `yahoo` or `ecb`.
        public var provider: String
        /// The symbol as the provider knows it, e.g. `VWCE.DE` or `EUR/USD`.
        public var symbol: String
        /// The check-in date.
        public var date: CalendarDate

        public init(provider: String, symbol: String, date: CalendarDate) {
            self.provider = provider
            self.symbol = symbol
            self.date = date
        }
    }

    private var entries: [Key: Task<any Sendable, any Error>] = [:]

    public init() {}

    /// The number of cached (or in-flight) values.
    public var count: Int { entries.count }

    /// Whether a value for `key` is cached or being fetched.
    public func contains(_ key: Key) -> Bool {
        entries[key] != nil
    }

    /// Forgets everything, so the next fetch asks the providers again.
    public func removeAll() {
        entries.removeAll()
    }

    /// The cached value for `key`, or the result of `fetch`, which is cached
    /// if it succeeds.
    func value<T: Sendable>(for key: Key, fetch: @escaping @Sendable () async throws -> T) async throws -> T {
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
