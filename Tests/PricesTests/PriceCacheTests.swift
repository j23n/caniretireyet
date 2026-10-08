import Foundation
import Model
@testable import Prices
import Testing
import TestSupport

/// Counts calls from concurrent tasks.
private actor Counter {
    private(set) var value = 0
    func increment() -> Int {
        value += 1
        return value
    }
}

struct PriceCacheTests {
    private let key = PriceCache.Key(provider: "yahoo", symbol: "VWCE.DE", date: "2026-09-30")

    @Test func concurrentRequestsShareOneFetch() async throws {
        let cache = PriceCache()
        let counter = Counter()
        let key = self.key
        let values = try await withThrowingTaskGroup(of: Int.self) { group in
            for _ in 0..<10 {
                group.addTask {
                    try await cache.value(for: key) {
                        try await Task.sleep(for: .milliseconds(20))
                        return await counter.increment()
                    }
                }
            }
            return try await group.reduce(into: []) { $0.append($1) }
        }
        #expect(values == Array(repeating: 1, count: 10))
        #expect(await counter.value == 1)
        #expect(await cache.contains(key))
    }

    @Test func failuresArentKept() async throws {
        let cache = PriceCache()
        await #expect(throws: PriceFetchError.cancelled) {
            _ = try await cache.value(for: key) { () async throws -> Int in throw PriceFetchError.cancelled }
        }
        #expect(await !cache.contains(key))
        #expect(try await cache.value(for: key) { 42 } == 42)
        #expect(try await cache.value(for: key) { 43 } == 42)

        await cache.removeAll()
        #expect(await !cache.contains(key))
    }

    @Test func aFailedItemIsFetchedAgainNextTime() async throws {
        let client = PriceServiceTests.client()
        await client.on("chart/RETRY", HTTPResponse(statusCode: 502, text: "Bad Gateway"),
                        HTTPResponse(statusCode: 200, text: PriceResponses.yahooVWCESeptember))
        var library = try Fixtures.exampleLibrary()
        library.instruments["vwce"]?.priceSource = PriceSource(provider: .yahoo, symbol: "RETRY")
        let service = PriceServiceTests.service(client)

        let first = await service.fetch(for: library, on: PriceServiceTests.checkIn)
        #expect(first.failures.map(\.item) == [.instrument("vwce")])
        #expect(first.failures.first?.failure?.isTransient == true)
        let second = await service.fetch(for: library, on: PriceServiceTests.checkIn)
        #expect(second.isComplete)
        #expect(await client.requests(matching: "chart/RETRY").count == 2)
        #expect(await client.requests(matching: "simple/price").count == 1)
    }
}
