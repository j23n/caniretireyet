import Foundation
import Model
@testable import Prices
import Testing
import TestSupport

struct GoldAPIProviderTests {
    private let today: CalendarDate = "2026-09-30"

    @Test func goldIsQuotedInUSDPerTroyOunce() async throws {
        let client = MockHTTPClient(["price/XAU": GoldAPIResponses.gold])
        let quote = try await GoldAPIProvider(client: client)
            .quote(for: QuoteRequest(symbol: "XAU", date: today, currency: .eur, today: today))
        #expect(quote.price == d("3488.45"))
        #expect(quote.currency == .usd)
        #expect(quote.unit == .troyOunce)
        #expect(quote.observedOn == today)
        #expect(quote.observedAt == Date(timeIntervalSince1970: 1_790_758_787))
        #expect(try #require(await client.requests.first).url.absoluteString == "https://api.gold-api.com/price/XAU")
    }

    @Test func silverWithoutACurrencyFieldIsUSD() async throws {
        let client = MockHTTPClient(["price/XAG": GoldAPIResponses.silver])
        let quote = try await GoldAPIProvider(client: client)
            .quote(for: QuoteRequest(symbol: "xag", date: today, currency: .eur, today: today))
        #expect(quote == Quote(price: d("41.28"), currency: .usd, unit: .troyOunce, observedOn: today,
                               observedAt: Date(timeIntervalSince1970: 1_790_758_787)))
    }

    @Test func aRecentCheckInUsesTodaysSpotPrice() async throws {
        let client = MockHTTPClient(["price/XAU": GoldAPIResponses.gold])
        let quote = try await GoldAPIProvider(client: client)
            .quote(for: QuoteRequest(symbol: "XAU", date: "2026-09-27", currency: .eur, today: today))
        #expect(quote.observedOn == today)
    }

    @Test func anOlderCheckInCantUseTheSpotPrice() async throws {
        let client = MockHTTPClient(["price/XAU": GoldAPIResponses.gold])
        let provider = GoldAPIProvider(client: client)
        do {
            _ = try await provider.quote(for: QuoteRequest(symbol: "XAU", date: "2026-06-30", currency: .eur,
                                                           today: today))
            Issue.record("Expected an error")
        } catch let error as PriceFetchError {
            #expect(error.description == "gold-api.com only has today's spot price, not one for 2026-06-30.")
        }
        #expect(await client.requestCount == 0)
    }

    @Test func anUnknownSymbolIsReported() async throws {
        let client = MockHTTPClient()
        await client.on("price/XYZ", HTTPResponse(statusCode: 404, text: GoldAPIResponses.unknownSymbol))
        await #expect(throws: PriceFetchError.unknownSymbol(service: "gold-api.com", symbol: "XYZ",
                                                            message: "Symbol not found")) {
            _ = try await GoldAPIProvider(client: client)
                .quote(for: QuoteRequest(symbol: "XYZ", date: today, currency: .eur, today: today))
        }
    }
}
