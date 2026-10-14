import Foundation
import Model
@testable import Prices
import Testing
import TestSupport

struct GoldAPIProviderTests {
    private let today: CalendarDate = "2026-09-30"

    @Test func goldIsQuotedInUSDPerTroyOunce() async throws {
        let client = MockHTTPClient(["price/XAU": PriceResponses.goldAPIGold])
        let quote = try await GoldAPIProvider(client: client).spot("XAU", today: today)
        #expect(quote.price == d("3488.45"))
        #expect(quote.currency == .usd)
        #expect(quote.unit == .troyOunce)
        #expect(quote.observedOn == today)
        #expect(try #require(await client.requests.first).url.absoluteString == "https://api.gold-api.com/price/XAU")
    }

    @Test func silverWithoutACurrencyFieldIsUSD() async throws {
        let client = MockHTTPClient(["price/XAG": GoldAPIResponses.silver])
        let quote = try await GoldAPIProvider(client: client).spot("xag", today: today)
        #expect(quote == Quote(price: d("41.28"), currency: .usd, unit: .troyOunce, observedOn: today))
    }

    /// The spot route covers the last three days, so a recent check-in uses
    /// today's spot price; it counts for any date it's asked for.
    @Test func aRecentCheckInUsesTodaysSpotPrice() async throws {
        let client = MockHTTPClient(["price/XAU": PriceResponses.goldAPIGold])
        let spot = try #require(GoldAPIProvider(client: client).routes(symbol: "XAU", today: today).first)
        #expect(spot.name == "gold-api.com · XAU")
        #expect(spot.covers("2026-09-27"))
        #expect(!spot.covers("2026-09-26"))
        #expect(spot.limitReason == "gold-api.com only has today's price.")
        let history = try await spot.fetch(HistoryRange(from: "2026-09-20", through: "2026-09-27", today: today))
        #expect(history.origin == QuoteOrigin(source: .goldAPI, service: "gold-api.com", symbol: "XAU"))
        #expect(history.quote(onOrBefore: "2026-09-27")?.observedOn == today)
    }

    @Test func anUnknownSymbolIsReported() async throws {
        let client = MockHTTPClient()
        await client.on("price/XYZ", HTTPResponse(statusCode: 404, text: GoldAPIResponses.unknownSymbol))
        await #expect(throws: PriceFetchError.unknownSymbol(service: "gold-api.com", symbol: "XYZ",
                                                            message: "Symbol not found")) {
            _ = try await GoldAPIProvider(client: client).spot("XYZ", today: today)
        }
    }
}
