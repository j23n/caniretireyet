import Foundation
import Model
@testable import Prices
import Testing
import TestSupport

struct YahooChartProviderTests {
    /// The quote a check-in on `date` gets: the latest close of the week
    /// before it.
    private func quote(_ fixture: String, _ symbol: String, on date: CalendarDate) async throws -> Quote? {
        let client = MockHTTPClient(["chart/": fixture])
        // Fetched on 2 October 2026, or on the date for a later one: bars
        // after the day two days after today don't exist yet, and are left out.
        let range = HistoryRange(from: date.adding(days: -PriceHistory.dailyTolerance), through: date,
                                 today: max(date, "2026-10-02"))
        return try await YahooChartProvider(client: client).history(symbol: symbol, range: range)
            .quote(onOrBefore: date)
    }

    @Test func theCloseOnTheDateRoundedToThePriceHint() async throws {
        let quote = try #require(try await quote(PriceResponses.yahooVWCESeptember, "VWCE.DE", on: "2026-09-30"))
        #expect(quote.price == d("138.42"))
        #expect(quote.currency == .eur)
        #expect(quote.unit == nil)
        #expect(quote.observedOn == "2026-09-30")
    }

    @Test func requestsTheDaysAroundTheDateWithABrowserUserAgent() async throws {
        let client = MockHTTPClient(["chart/": PriceResponses.yahooVWCESeptember])
        let range = HistoryRange(from: "2026-09-23", through: "2026-09-30", monthEndsOnly: true, today: "2026-09-30")
        let history = try await YahooChartProvider(client: client).history(symbol: "VWCE.DE", range: range)
        #expect(history.origin == QuoteOrigin(source: .yahoo, service: "Yahoo Finance", symbol: "VWCE.DE"))
        #expect(history.spacing == .daily)
        let sent = try #require(await client.requests.first)
        #expect(sent.url.absoluteString == "https://query1.finance.yahoo.com/v8/finance/chart/VWCE.DE"
            + "?period1=1790035200&period2=1790899200&interval=1d&includePrePost=false")
        #expect(sent.headers["User-Agent"] == "Mozilla/5.0")
    }

    @Test func nullClosesAreSkipped() async throws {
        let quote = try #require(try await quote(PriceResponses.yahooVWCESeptember, "VWCE.DE", on: "2026-09-29"))
        #expect(quote.price == d("137.64"))
        #expect(quote.observedOn == "2026-09-28")
    }

    @Test func tradingDaysAreInTheExchangesTimeZone() async throws {
        // The bar for Wednesday 30 September in Auckland is stamped 21:00 UTC
        // on the 29th, so it must not count for a check-in on the 29th.
        let quote = try #require(try await quote(YahooResponses.fphAuckland, "FPH.NZ", on: "2026-09-29"))
        #expect(quote.price == d("38.7"))
        #expect(quote.observedOn == "2026-09-29")
        #expect(quote.currency == "NZD")
    }

    @Test func penceBecomePounds() async throws {
        let quote = try #require(try await quote(YahooResponses.vwrlPence, "VWRL.L", on: "2026-09-30"))
        #expect(quote.price == d("105.235"))
        #expect(quote.currency == .gbp)
        #expect(YahooChartProvider.majorUnit(of: "ZAc") == ("ZAR", 100))
        #expect(YahooChartProvider.majorUnit(of: "usd") == (.usd, 1))
    }

    @Test func anUnknownSymbolIsReported() async throws {
        let client = MockHTTPClient()
        await client.on("chart/", HTTPResponse(statusCode: 404, text: YahooResponses.notFound))
        do {
            _ = try await YahooChartProvider(client: client).history(
                symbol: "NOPE.DE", range: HistoryRange(from: "2026-09-23", through: "2026-09-30", today: "2026-09-30"))
            Issue.record("Expected an error")
        } catch let error as PriceFetchError {
            #expect(error == .unknownSymbol(service: "Yahoo Finance", symbol: "NOPE.DE",
                                            message: "No data found, symbol may be delisted"))
        }
    }

    /// No bars, or none in the week before the date: no quote.
    @Test func noBarsIsNoQuote() async throws {
        #expect(try await quote(YahooResponses.noBars, "VWCE.DE", on: "2026-09-30") == nil)
        #expect(try await quote(PriceResponses.yahooVWCESeptember, "VWCE.DE", on: "2026-09-10") == nil)
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
        let quote = try #require(try await quote(response, "VWCE.DE", on: "2026-09-30"))
        #expect(quote.price == d("137.64"))
        #expect(quote.observedOn == "2026-09-29")

        let client = MockHTTPClient(["chart/": response])
        let history = try await YahooChartProvider(client: client).history(
            symbol: "VWCE.DE", range: HistoryRange(from: "2026-09-01", through: "2026-09-30", today: "2026-10-02"))
        #expect(history.quotes.map(\.observedOn) == ["2026-09-29"])
    }
}
