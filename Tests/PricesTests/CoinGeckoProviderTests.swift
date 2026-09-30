import Foundation
import Model
@testable import Prices
import Testing

private func d(_ string: String) -> Decimal { Decimal(fileString: string)! }

struct CoinGeckoProviderTests {
    private let today: CalendarDate = "2026-09-30"

    private func request(_ date: CalendarDate, _ currency: CurrencyCode = .usd, symbol: String = "bitcoin") -> QuoteRequest {
        QuoteRequest(symbol: symbol, date: date, currency: currency, today: today)
    }

    @Test func todayUsesTheSpotPriceInTheInstrumentsCurrency() async throws {
        let client = MockHTTPClient(["simple/price": CoinGeckoResponses.spotUSD])
        let quote = try await CoinGeckoProvider(client: client).quote(for: request(today))
        #expect(quote.price == 111_400)
        #expect(quote.currency == .usd)
        #expect(quote.unit == nil)
        #expect(quote.observedOn == today)
        #expect(quote.observedAt == Date(timeIntervalSince1970: 1_790_758_680))

        let sent = try #require(await client.requests.first)
        #expect(sent.url.absoluteString == "https://api.coingecko.com/api/v3/simple/price?ids=bitcoin"
            + "&vs_currencies=usd&include_last_updated_at=true&precision=full")
        #expect(sent.headers[CoinGeckoProvider.apiKeyHeader] == nil)
    }

    @Test func aPastDateUsesTheSnapshotAtTheEndOfThatDay() async throws {
        let client = MockHTTPClient(["coins/bitcoin/history": CoinGeckoResponses.historyEndOfMarch])
        let provider = CoinGeckoProvider(client: client)

        let usd = try await provider.quote(for: request("2026-03-31"))
        #expect(usd.price == d("88900.12"))
        #expect(usd.observedOn == "2026-03-31")
        let eur = try await provider.quote(for: request("2026-03-31", .eur))
        #expect(eur == Quote(price: d("80076.47"), currency: .eur, observedOn: "2026-03-31",
                             observedAt: Date(timeIntervalSince1970: 1_775_001_600)))

        let sent = try #require(await client.requests.first)
        #expect(sent.url.absoluteString
            == "https://api.coingecko.com/api/v3/coins/bitcoin/history?date=01-04-2026&localization=false")
    }

    @Test func sendsTheDemoKeyInAHeaderNotTheURL() async throws {
        let client = MockHTTPClient(["simple/price": CoinGeckoResponses.spotEUR])
        let credentials = StaticCredentials([.coingecko: "CG-demo-made-up-key"])
        let quote = try await CoinGeckoProvider(client: client, credentials: credentials).quote(for: request(today, .eur))
        #expect(quote.price == d("97736.4568"))

        let sent = try #require(await client.requests.first)
        #expect(sent.headers["x-cg-demo-api-key"] == "CG-demo-made-up-key")
        #expect(!sent.url.absoluteString.contains("CG-demo"))
    }

    @Test func blankKeysAreNotSent() async throws {
        let client = MockHTTPClient(["simple/price": CoinGeckoResponses.spotUSD])
        let credentials = StaticCredentials([.coingecko: "  "])
        _ = try await CoinGeckoProvider(client: client, credentials: credentials).quote(for: request(today))
        #expect(try #require(await client.requests.first).headers.isEmpty)
    }

    @Test func aRateLimitIsRetriedWhenTheWaitIsShort() async throws {
        let client = MockHTTPClient()
        await client.on(
            "simple/price",
            HTTPResponse(statusCode: 429, headers: ["Retry-After": "0"], text: CoinGeckoResponses.rateLimited),
            HTTPResponse(statusCode: 200, text: CoinGeckoResponses.spotUSD))
        let quote = try await CoinGeckoProvider(client: client).quote(for: request(today))
        #expect(quote.price == 111_400)
        #expect(await client.requestCount == 2)
    }

    @Test func aPersistentRateLimitIsReported() async throws {
        let client = MockHTTPClient()
        await client.on("simple/price",
                        HTTPResponse(statusCode: 429, headers: ["Retry-After": "30"], text: CoinGeckoResponses.rateLimited))
        await #expect(throws: PriceFetchError.rateLimited(service: "CoinGecko", retryAfter: .seconds(30))) {
            _ = try await CoinGeckoProvider(client: client).quote(for: request(today))
        }
    }

    @Test func anUnknownCoinIsReported() async throws {
        let spot = MockHTTPClient(["simple/price": CoinGeckoResponses.spotUnknown])
        await #expect(throws: PriceFetchError.unknownSymbol(service: "CoinGecko", symbol: "not-a-coin", message: nil)) {
            _ = try await CoinGeckoProvider(client: spot).quote(for: request(today, symbol: "not-a-coin"))
        }

        let history = MockHTTPClient()
        await history.on("history", HTTPResponse(statusCode: 404, text: CoinGeckoResponses.coinNotFound))
        await #expect(throws: PriceFetchError.unknownSymbol(service: "CoinGecko", symbol: "not-a-coin",
                                                            message: "coin not found")) {
            _ = try await CoinGeckoProvider(client: history).quote(for: request("2026-03-31", symbol: "not-a-coin"))
        }
    }

    @Test func aSnapshotWithoutMarketDataIsNoData() async throws {
        let client = MockHTTPClient(["history": CoinGeckoResponses.historyWithoutMarketData])
        await #expect(throws: PriceFetchError.noData(service: "CoinGecko",
                                                     detail: "no USD price for bitcoin on 2026-03-31")) {
            _ = try await CoinGeckoProvider(client: client).quote(for: request("2026-03-31"))
        }
    }

    @Test func yesterdayFallsBackToSpotWhenTodaysSnapshotIsMissing() async throws {
        let client = MockHTTPClient([
            "history": CoinGeckoResponses.historyWithoutMarketData, "simple/price": CoinGeckoResponses.spotUSD,
        ])
        let quote = try await CoinGeckoProvider(client: client).quote(for: request("2026-09-29"))
        #expect(quote.price == 111_400)
        #expect(await client.requestCount == 2)
    }

    @Test func refusalsExplainThemselves() async throws {
        let client = MockHTTPClient()
        await client.on("history", HTTPResponse(statusCode: 401, text: CoinGeckoResponses.beyondTimeRange))
        do {
            _ = try await CoinGeckoProvider(client: client).quote(for: request("2024-06-30"))
            Issue.record("Expected an error")
        } catch let error as PriceFetchError {
            guard case .unauthorized(_, let message) = error else {
                Issue.record("Unexpected \(error)")
                return
            }
            #expect(message?.hasPrefix("Your request exceeds the allowed time range.") == true)
        }

        let wrongKey = MockHTTPClient()
        await wrongKey.on("simple/price", HTTPResponse(statusCode: 400, text: CoinGeckoResponses.wrongKey))
        do {
            _ = try await CoinGeckoProvider(client: wrongKey).quote(for: request(today))
            Issue.record("Expected an error")
        } catch let error as PriceFetchError {
            #expect(error.description.contains("pro-api.coingecko.com"))
        }
    }

    @Test func theCacheKeyIncludesTheCurrency() {
        let provider = CoinGeckoProvider(client: MockHTTPClient())
        #expect(provider.cacheSymbol(for: request(today, .eur)) == "bitcoin/EUR")
    }

    @Test func historyDatesAreDayMonthYear() {
        #expect(CoinGeckoProvider.historyDate("2026-04-01") == "01-04-2026")
        #expect(CoinGeckoProvider.historyDate("2025-12-31") == "31-12-2025")
    }
}
