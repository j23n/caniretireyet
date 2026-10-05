import Foundation
import Model
@testable import Prices
import Testing

private func d(_ string: String) -> Decimal { Decimal(fileString: string)! }

struct YahooChartProviderTests {
    private func quote(_ fixture: String, _ symbol: String, on date: CalendarDate) async throws -> Quote {
        let client = MockHTTPClient(["chart/": fixture])
        // Fetched on 2 October 2026, or on the date for a later one: bars
        // after the day two days after today don't exist yet, and are left out.
        return try await YahooChartProvider(client: client)
            .quote(for: QuoteRequest(symbol: symbol, date: date, currency: .eur, today: max(date, "2026-10-02")))
    }

    @Test func theCloseOnTheDateRoundedToThePriceHint() async throws {
        let quote = try await quote(YahooResponses.vwceSeptember, "VWCE.DE", on: "2026-09-30")
        #expect(quote.price == d("138.42"))
        #expect(quote.currency == .eur)
        #expect(quote.unit == nil)
        #expect(quote.observedOn == "2026-09-30")
        #expect(quote.observedAt == Date(timeIntervalSince1970: 1_790_751_600))
    }

    @Test func requestsTheDaysAroundTheDateWithABrowserUserAgent() async throws {
        let client = MockHTTPClient(["chart/": YahooResponses.vwceSeptember])
        _ = try await YahooChartProvider(client: client)
            .quote(for: QuoteRequest(symbol: "VWCE.DE", date: "2026-09-30", currency: .eur, today: "2026-09-30"))
        let sent = try #require(await client.requests.first)
        #expect(sent.url.absoluteString == "https://query1.finance.yahoo.com/v8/finance/chart/VWCE.DE"
            + "?period1=1789516800&period2=1790899200&interval=1d&includePrePost=false")
        #expect(sent.headers["User-Agent"] == "Mozilla/5.0")
    }

    @Test func aWeekendGetsFridaysClose() async throws {
        let quote = try await quote(YahooResponses.vwceSeptember, "VWCE.DE", on: "2026-09-27")
        #expect(quote.price == d("136.88"))
        #expect(quote.observedOn == "2026-09-25")
    }

    @Test func nullClosesAreSkipped() async throws {
        let quote = try await quote(YahooResponses.vwceSeptember, "VWCE.DE", on: "2026-09-29")
        #expect(quote.price == d("137.64"))
        #expect(quote.observedOn == "2026-09-28")
    }

    @Test func closesAfterTheDateAreIgnored() async throws {
        // The response also has 1 October, e.g. when fetched later.
        let quote = try await quote(YahooResponses.vwceSeptember, "VWCE.DE", on: "2026-09-30")
        #expect(quote.observedOn == "2026-09-30")
    }

    @Test func aHolidayGetsTheLastTradingDay() async throws {
        let christmasEve = try await quote(YahooResponses.vwceChristmas, "VWCE.DE", on: "2026-12-24")
        #expect(christmasEve.price == d("142.92"))
        #expect(christmasEve.observedOn == "2026-12-23")
        let sunday = try await quote(YahooResponses.vwceChristmas, "VWCE.DE", on: "2026-12-27")
        #expect(sunday.observedOn == "2026-12-23")
        let monday = try await quote(YahooResponses.vwceChristmas, "VWCE.DE", on: "2026-12-28")
        #expect(monday.price == d("143.1"))
    }

    @Test func tradingDaysAreInTheExchangesTimeZone() async throws {
        // The bar for Wednesday 30 September in Auckland is stamped 21:00 UTC
        // on the 29th, so it must not count for a check-in on the 29th.
        let quote = try await quote(YahooResponses.fphAuckland, "FPH.NZ", on: "2026-09-29")
        #expect(quote.price == d("38.7"))
        #expect(quote.observedOn == "2026-09-29")
        #expect(quote.currency == "NZD")
    }

    @Test func penceBecomePounds() async throws {
        let quote = try await quote(YahooResponses.vwrlPence, "VWRL.L", on: "2026-09-30")
        #expect(quote.price == d("105.235"))
        #expect(quote.currency == .gbp)
        #expect(YahooChartProvider.majorUnit(of: "ZAc") == ("ZAR", 100))
        #expect(YahooChartProvider.majorUnit(of: "usd") == (.usd, 1))
    }

    @Test func anUnknownSymbolIsReported() async throws {
        let client = MockHTTPClient()
        await client.on("chart/", HTTPResponse(statusCode: 404, text: YahooResponses.notFound))
        let request = QuoteRequest(symbol: "NOPE.DE", date: "2026-09-30", currency: .eur, today: "2026-09-30")
        do {
            _ = try await YahooChartProvider(client: client).quote(for: request)
            Issue.record("Expected an error")
        } catch let error as PriceFetchError {
            #expect(error == .unknownSymbol(service: "Yahoo Finance", symbol: "NOPE.DE",
                                            message: "No data found, symbol may be delisted"))
            #expect(error.description
                == "Yahoo Finance doesn't know \"NOPE.DE\": No data found, symbol may be delisted.")
        }
    }

    @Test func anUnexpectedShapeFailsClearly() async throws {
        await #expect(throws: PriceFetchError.malformedResponse(
            service: "Yahoo Finance", detail: "missing chart.result[0].indicators.quote[0].close")) {
            _ = try await quote(YahooResponses.withoutIndicators, "VWCE.DE", on: "2026-09-30")
        }
        await #expect(throws: PriceFetchError.malformedResponse(service: "Yahoo Finance", detail: "not JSON")) {
            _ = try await quote("<html>Yahoo is down</html>", "VWCE.DE", on: "2026-09-30")
        }
        await #expect(throws: PriceFetchError.malformedResponse(service: "Yahoo Finance",
                                                                detail: "unexpected value at chart.result[0].timestamp")) {
            _ = try await quote(#"{"chart":{"result":[{"timestamp":"soon"}]}}"#, "VWCE.DE", on: "2026-09-30")
        }
    }

    @Test func noBarsIsNoData() async throws {
        await #expect(throws: PriceFetchError.noData(service: "Yahoo Finance",
                                                     detail: "no trading days for VWCE.DE up to 2026-09-30")) {
            _ = try await quote(YahooResponses.noBars, "VWCE.DE", on: "2026-09-30")
        }
        await #expect(throws: PriceFetchError.noData(service: "Yahoo Finance",
                                                     detail: "no close for VWCE.DE on or before 2026-09-10")) {
            _ = try await quote(YahooResponses.vwceSeptember, "VWCE.DE", on: "2026-09-10")
        }
    }

    /// A timestamp in milliseconds is about the year 58,700: converting it
    /// to a calendar date would trap, so the bar is left out, as is one
    /// before 1970.
    @Test func timestampsOutsideTheirPlausibleRangeAreLeftOut() async throws {
        let response = """
            {"chart":{"result":[{"meta":{"currency":"EUR","exchangeTimezoneName":"Europe/Berlin","priceHint":2},\
            "timestamp":[-86400,1790665200,1790751600000],\
            "indicators":{"quote":[{"close":[1.0,137.63999938964844,999.0]}]}}],"error":null}}
            """
        let quote = try await quote(response, "VWCE.DE", on: "2026-09-30")
        #expect(quote.price == d("137.64"))
        #expect(quote.observedOn == "2026-09-29")

        let client = MockHTTPClient(["chart/": response])
        let history = try await YahooChartProvider(client: client).history(
            symbol: "VWCE.DE", range: HistoryRange(from: "2026-09-01", through: "2026-09-30", today: "2026-10-02"))
        #expect(history.quotes.map(\.observedOn) == ["2026-09-29"])
    }

    @Test func tooManyRequestsIsARateLimit() async throws {
        let client = MockHTTPClient()
        await client.on("chart/", HTTPResponse(statusCode: 429, text: YahooResponses.tooManyRequests))
        let provider = YahooChartProvider(client: client, policy: RequestPolicy(maxRetries: 0))
        await #expect(throws: PriceFetchError.rateLimited(service: "Yahoo Finance", retryAfter: nil)) {
            _ = try await provider.quote(for: QuoteRequest(symbol: "VWCE.DE", date: "2026-09-30", currency: .eur,
                                                           today: "2026-09-30"))
        }
    }
}
