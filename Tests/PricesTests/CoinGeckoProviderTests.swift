import Foundation
import Model
@testable import Prices
import Testing
import TestSupport

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
        let unknown = PriceFetchError.unknownSymbol(service: "CoinGecko", symbol: "not-a-coin",
                                                    message: CoinGeckoProvider.unknownCoinAdvice)
        let spot = MockHTTPClient([
            "simple/price": CoinGeckoResponses.spotUnknown, "search": CoinGeckoResponses.searchNoMatch,
        ])
        await #expect(throws: unknown) {
            _ = try await CoinGeckoProvider(client: spot).quote(for: request(today, symbol: "not-a-coin"))
        }

        let history = MockHTTPClient()
        await history.on("history", HTTPResponse(statusCode: 404, text: CoinGeckoResponses.coinNotFound))
        await history.on("search", json: CoinGeckoResponses.searchNoMatch)
        await #expect(throws: unknown) {
            _ = try await CoinGeckoProvider(client: history).quote(for: request("2026-03-31", symbol: "not-a-coin"))
        }
    }

    // MARK: - Tickers and coin IDs

    @Test func aTickerResolvesThroughTheTableWithoutSearching() async throws {
        let client = MockHTTPClient(["simple/price": CoinGeckoResponses.spotEthereumEUR])
        let provider = CoinGeckoProvider(client: client)
        // As typed, and as the instrument form's slug of the name suggests it.
        for symbol in ["ETH", "eth", "Eth"] {
            let quote = try await provider.quote(for: request(today, .eur, symbol: symbol))
            #expect(quote.price == d("3812.0625"))
            #expect(quote.resolvedSymbol == "ethereum")
        }
        #expect(await client.requests(matching: "search").isEmpty)
        #expect(try #require(await client.requests.first).url.absoluteString
            == "https://api.coingecko.com/api/v3/simple/price?ids=ethereum"
            + "&vs_currencies=eur&include_last_updated_at=true&precision=full")
    }

    @Test func historyWorksWithAResolvedID() async throws {
        let client = MockHTTPClient(["coins/ethereum/history": CoinGeckoResponses.historyEthereumEndOfMarch])
        let quote = try await CoinGeckoProvider(client: client).quote(for: request("2026-03-31", .eur, symbol: "ETH"))
        #expect(quote == Quote(price: d("1612.34"), currency: .eur, observedOn: "2026-03-31",
                               observedAt: Date(timeIntervalSince1970: 1_775_001_600), resolvedSymbol: "ethereum"))
        #expect(await client.requests.map(\.url.absoluteString) == [
            "https://api.coingecko.com/api/v3/coins/ethereum/history?date=01-04-2026&localization=false",
        ])
    }

    /// A market chart's times are milliseconds. One given in microseconds
    /// (beyond year 9999) or negative is left out instead of trapping when
    /// it's turned into a date.
    @Test func marketChartTimesOutsideTheirPlausibleRangeAreLeftOut() async throws {
        let client = MockHTTPClient(["market_chart/range": """
            { "prices": [[-86400000, 1.0], [1790726400000, 3871.2], [1790726400000000, 9.9]] }
            """])
        let history = try await CoinGeckoProvider(client: client).history(
            symbol: "ethereum", currency: .eur,
            range: HistoryRange(from: "2026-09-25", through: "2026-09-30", today: today))
        #expect(history.quotes.map(\.observedOn) == ["2026-09-29"])
        #expect(history.quotes.map(\.price) == [d("3871.2")])
    }

    @Test func anUnknownTickerResolvesThroughSearchToTheBestRankedCoin() async throws {
        let client = MockHTTPClient([
            "search": CoinGeckoResponses.searchMoon, "simple/price": CoinGeckoResponses.spotMoonstoneUSD,
        ])
        let credentials = StaticCredentials([.coingecko: "CG-demo-made-up-key"])
        let quote = try await CoinGeckoProvider(client: client, credentials: credentials)
            .quote(for: request(today, symbol: "MOON"))
        #expect(quote.price == d("0.4187"))
        #expect(quote.resolvedSymbol == "moonstone")

        let sent = await client.requests
        #expect(sent.map(\.url.absoluteString) == [
            "https://api.coingecko.com/api/v3/search?query=MOON",
            "https://api.coingecko.com/api/v3/simple/price?ids=moonstone"
                + "&vs_currencies=usd&include_last_updated_at=true&precision=full",
        ])
        #expect(sent.allSatisfy { $0.headers[CoinGeckoProvider.apiKeyHeader] == "CG-demo-made-up-key" })
    }

    @Test func anIDPassesThrough() async throws {
        let client = MockHTTPClient(["simple/price": CoinGeckoResponses.spotMoonstoneUSD])
        let quote = try await CoinGeckoProvider(client: client).quote(for: request(today, symbol: "moonstone"))
        #expect(quote.price == d("0.4187"))
        #expect(quote.resolvedSymbol == nil)
        #expect(await client.requestCount == 1)
        #expect(await client.requests(matching: "search").isEmpty)
    }

    @Test func anIDCoinGeckoDoesntKnowFallsBackToSearch() async throws {
        // "moon" looks like an ID, so it's tried first; CoinGecko has no such coin.
        let client = MockHTTPClient()
        await client.on("coins/moon/history", HTTPResponse(statusCode: 404, text: CoinGeckoResponses.coinNotFound))
        await client.on("search", json: CoinGeckoResponses.searchMoon)
        await client.on("coins/moonstone/history", json: CoinGeckoResponses.historyMoonstone)

        let quote = try await CoinGeckoProvider(client: client).quote(for: request("2026-03-31", .eur, symbol: "moon"))
        #expect(quote.price == d("0.3561"))
        #expect(quote.resolvedSymbol == "moonstone")
        #expect(await client.requests.map(\.url.path) == [
            "/api/v3/coins/moon/history", "/api/v3/search", "/api/v3/coins/moonstone/history",
        ])
    }

    @Test func noMatchExplainsWhatToEnter() async throws {
        let client = MockHTTPClient(["search": CoinGeckoResponses.searchNoMatch])
        let provider = CoinGeckoProvider(client: client)
        do {
            _ = try await provider.quote(for: request(today, symbol: "XYZ"))
            Issue.record("Expected an error")
        } catch let error as PriceFetchError {
            #expect(error == .unknownSymbol(service: "CoinGecko", symbol: "XYZ",
                                            message: CoinGeckoProvider.unknownCoinAdvice))
            #expect(error.description == "CoinGecko doesn't know \"XYZ\". Use the coin's API ID from its page "
                + "on coingecko.com (e.g. ethereum) or its ticker.")
        }
        // The answer is remembered: asking again doesn't search again.
        await #expect(throws: PriceFetchError.self) {
            _ = try await provider.quote(for: request("2026-03-31", symbol: "xyz"))
        }
        #expect(await client.requestCount == 1)
    }

    @Test func aResolutionIsRememberedAcrossDates() async throws {
        let client = MockHTTPClient([
            "search": CoinGeckoResponses.searchMoon, "coins/moonstone/history": CoinGeckoResponses.historyMoonstone,
        ])
        let provider = CoinGeckoProvider(client: client)
        async let march = provider.quote(for: request("2026-03-31", symbol: "MOON"))
        async let june = provider.quote(for: request("2026-06-30", symbol: "MOON"))
        let quotes = try await [march, june]
        #expect(quotes.map(\.price) == [d("0.3952"), d("0.3952")])
        #expect(quotes.map(\.resolvedSymbol) == ["moonstone", "moonstone"])
        #expect(await client.requests(matching: "search").count == 1)
        #expect(await client.requests(matching: "coins/moonstone/history").count == 2)

        // An ID that fell back to search isn't tried again either.
        let fallback = MockHTTPClient([
            "search": CoinGeckoResponses.searchMoon, "coins/moonstone/history": CoinGeckoResponses.historyMoonstone,
        ])
        await fallback.on("coins/moon/history", HTTPResponse(statusCode: 404, text: CoinGeckoResponses.coinNotFound))
        let other = CoinGeckoProvider(client: fallback)
        for date: CalendarDate in ["2026-03-31", "2026-06-30"] {
            #expect(try await other.quote(for: request(date, symbol: "moon")).resolvedSymbol == "moonstone")
        }
        #expect(await fallback.requests(matching: "coins/moon/history").count == 1)
        #expect(await fallback.requests(matching: "search").count == 1)
    }

    @Test func aFailedSearchIsTriedAgain() async throws {
        let client = MockHTTPClient()
        await client.on("search", HTTPResponse(statusCode: 500, text: "Internal Server Error"),
                        HTTPResponse(statusCode: 200, text: CoinGeckoResponses.searchMoon))
        await client.on("simple/price", json: CoinGeckoResponses.spotMoonstoneUSD)
        let provider = CoinGeckoProvider(client: client)
        await #expect(throws: PriceFetchError.httpStatus(service: "CoinGecko", code: 500,
                                                         message: "Internal Server Error")) {
            _ = try await provider.quote(for: request(today, symbol: "MOON"))
        }
        #expect(try await provider.quote(for: request(today, symbol: "MOON")).resolvedSymbol == "moonstone")
        #expect(await client.requests(matching: "search").count == 2)
    }

    @Test func searchPrefersAnExactIDThenTheBestRankedTicker() {
        typealias Coin = CoinGeckoCoinIDs.SearchCoin
        let coins = [
            Coin(id: "moon-token", symbol: "MOON", marketCapRank: nil),
            Coin(id: "moonstone", symbol: "moon", marketCapRank: 287),
            Coin(id: "moon-dao", symbol: "MOON", marketCapRank: 287),
            Coin(id: "moon", symbol: "LUNAR", marketCapRank: 5000),
        ]
        // An exact ID wins over any ticker, whatever its rank.
        #expect(CoinGeckoCoinIDs.bestMatch(for: "Moon", in: coins) == "moon")
        // Among tickers, the lowest rank; ties go to the first listed.
        #expect(CoinGeckoCoinIDs.bestMatch(for: "MOON", in: Array(coins.dropLast())) == "moonstone")
        // Unranked coins come last, but still match.
        #expect(CoinGeckoCoinIDs.bestMatch(for: "MOON", in: [coins[0]]) == "moon-token")
        #expect(CoinGeckoCoinIDs.bestMatch(for: "LUNA", in: coins) == nil)
        #expect(CoinGeckoCoinIDs.bestMatch(for: "MOON", in: []) == nil)
    }

    @Test func onlyLowercaseSymbolsLookLikeIDs() {
        for symbol in ["bitcoin", "avalanche-2", "usd-coin"] { #expect(CoinGeckoCoinIDs.looksLikeCoinID(symbol)) }
        for symbol in ["", "BTC", "Bitcoin", "wrapped bitcoin", "$moon"] {
            #expect(!CoinGeckoCoinIDs.looksLikeCoinID(symbol))
        }
    }

    @Test func theTickerTableHoldsIDs() {
        #expect(CoinGeckoCoinIDs.tickers.count >= 17)
        for (ticker, id) in CoinGeckoCoinIDs.tickers {
            #expect(ticker == ticker.uppercased())
            #expect(CoinGeckoCoinIDs.looksLikeCoinID(id), "\(ticker) → \(id)")
        }
        #expect(CoinGeckoCoinIDs.coinID(forTicker: "avax") == "avalanche-2")
        #expect(CoinGeckoCoinIDs.coinID(forTicker: "bitcoin") == nil)
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
        // The library's symbol, not the coin it resolves to.
        #expect(provider.cacheSymbol(for: request(today, .eur, symbol: "ETH")) == "ETH/EUR")
    }

    @Test func historyDatesAreDayMonthYear() {
        #expect(CoinGeckoProvider.historyDate("2026-04-01") == "01-04-2026")
        #expect(CoinGeckoProvider.historyDate("2025-12-31") == "31-12-2025")
    }
}
