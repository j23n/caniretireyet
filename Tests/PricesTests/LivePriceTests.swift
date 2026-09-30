import Foundation
import Model
import Prices
import Testing
import TestSupport

/// Smoke tests against the real APIs. They run only with
/// `LIVE_PRICE_TESTS=1 swift test --filter LivePriceTests`, and read an
/// optional CoinGecko demo key from `COINGECKO_API_KEY`.
@Suite(.enabled(if: ProcessInfo.processInfo.environment["LIVE_PRICE_TESTS"] == "1"), .serialized)
struct LivePriceTests {
    private let today = CalendarDate.today(in: TimeZone(identifier: "Europe/Rome")!)

    private var credentials: StaticCredentials {
        StaticCredentials([.coingecko: ProcessInfo.processInfo.environment["COINGECKO_API_KEY"] ?? ""])
    }

    @Test func eachProviderAnswers() async throws {
        let usd = try await FrankfurterProvider().rate(base: .eur, quote: .usd, onOrBefore: today)
        #expect(usd.rate > 0.5 && usd.rate < 2)

        let request = { (symbol: String, currency: CurrencyCode) in
            QuoteRequest(symbol: symbol, date: today, currency: currency, today: today)
        }
        let coinGecko = CoinGeckoProvider(credentials: credentials)
        let btc = try await coinGecko.quote(for: request("bitcoin", .eur))
        #expect(btc.price > 1000)
        // A ticker from the built-in table, and one CoinGecko's search resolves.
        let eth = try await coinGecko.quote(for: request("ETH", .eur))
        #expect(eth.resolvedSymbol == "ethereum" && eth.price > 100)
        let pepe = try await coinGecko.quote(for: request("PEPE", .usd))
        #expect(pepe.resolvedSymbol != nil && pepe.price > 0)
        let gold = try await GoldAPIProvider().quote(for: request("XAU", .usd))
        #expect(gold.unit == .troyOunce && gold.price > 500)
        let vwce = try await YahooChartProvider().quote(for: request("VWCE.DE", .eur))
        #expect(vwce.currency == .eur && vwce.price > 10)

        let hicp = try await EurostatIndexProvider()
            .values(from: today.yearMonth.adding(months: -6), through: today.yearMonth)
        #expect(!hicp.isEmpty)
        #expect(hicp.allSatisfy { $0.date.isEndOfMonth && $0.value > 100 })
    }

    @Test func theServiceFetchesTheExampleLibrary() async throws {
        let service = PriceService.standard(credentials: credentials)
        let result = await service.fetch(for: try Fixtures.exampleLibrary(), on: today)
        for failure in result.failures {
            Issue.record("\(failure.item): \(failure.failureReason ?? "")")
        }
        #expect(result.prices.count == 3)
    }
}
