import Foundation
import Model
@testable import Prices
import Testing
import TestSupport

/// Ranged histories: picking a date's value, and each provider's range
/// request and parsing, against recorded responses.
struct PriceHistoryTests {
    private let today: CalendarDate = "2026-09-30"

    private func quote(_ day: CalendarDate, _ price: String) -> Quote {
        Quote(price: d(price), currency: .eur, observedOn: day)
    }

    // MARK: Picking

    @Test func aDateTakesTheLatestValueOnOrBeforeItAcrossWeekends() {
        // Mon 21 to Fri 25 September, Mon 28, no close on Tue 29, Wed 30.
        let history = PriceHistory(quotes: [
            quote("2026-09-21", "135.88"), quote("2026-09-22", "136.44"), quote("2026-09-23", "137.1"),
            quote("2026-09-24", "136.52"), quote("2026-09-25", "136.88"), quote("2026-09-28", "137.64"),
            quote("2026-09-30", "138.42"),
        ])
        #expect(history.quote(onOrBefore: "2026-09-27")?.observedOn == "2026-09-25") // Sunday: Friday's
        #expect(history.quote(onOrBefore: "2026-09-26")?.price == d("136.88"))
        #expect(history.quote(onOrBefore: "2026-09-29")?.observedOn == "2026-09-28") // A day without a close
        #expect(history.quote(onOrBefore: "2026-09-30")?.price == d("138.42"))
        #expect(history.quote(onOrBefore: "2026-10-04")?.observedOn == "2026-09-30")
        #expect(history.quote(onOrBefore: "2026-09-20") == nil) // Before the first
    }

    @Test func aValueCountsForAWeekAtMost() {
        let history = PriceHistory(quotes: [quote("2026-08-31", "100"), quote("2026-09-21", "110")])
        #expect(history.quote(onOrBefore: "2026-09-07")?.observedOn == "2026-08-31") // 7 days
        #expect(history.quote(onOrBefore: "2026-09-08") == nil) // 8 days: a gap in the data
    }

    @Test func aMonthlyValueCountsForItsOwnMonth() {
        let history = PriceHistory(quotes: [quote("2026-07-31", "3395.7"), quote("2026-08-31", "3516.6")],
                                   spacing: .monthly)
        #expect(history.quote(onOrBefore: "2026-08-31")?.price == d("3516.6"))
        #expect(history.quote(onOrBefore: "2026-08-15") == nil) // July's close is a month old
        #expect(history.quote(onOrBefore: "2026-09-30") == nil)
    }

    @Test func ofTwoQuotesOnADayTheLastGivenWins() {
        let history = PriceHistory(quotes: [quote("2026-09-30", "3480.1"), quote("2026-09-30", "3488.45")])
        #expect(history.quotes.count == 1)
        #expect(history.quote(onOrBefore: "2026-09-30")?.price == d("3488.45"))
    }

    @Test func weeklyRatesCountForTwoWeeks() {
        let daily = FXHistory(rates: [
            FXObservation(rate: d("1.1371"), observedOn: "2026-09-25"),
            FXObservation(rate: d("1.1385"), observedOn: "2026-09-28"),
            FXObservation(rate: d("1.139"), observedOn: "2026-09-29"),
        ])
        #expect(!daily.isWeekly)
        #expect(daily.rate(onOrBefore: "2026-09-27")?.rate == d("1.1371"))
        #expect(daily.rate(onOrBefore: "2026-10-07") == nil)

        let weekly = FXHistory(rates: ["2025-08-11", "2025-08-18", "2025-08-25"].map {
            FXObservation(rate: 1, observedOn: CalendarDate($0)!)
        })
        #expect(weekly.isWeekly)
        #expect(weekly.rate(onOrBefore: "2025-09-07")?.observedOn == "2025-08-25") // 13 days
        #expect(weekly.rate(onOrBefore: "2025-09-09") == nil)
    }

    // MARK: Yahoo Finance

    @Test func aYahooRangeIsOneDailyRequest() async throws {
        let client = MockHTTPClient(["chart/": PriceResponses.yahooVWCESeptember])
        let history = try await YahooChartProvider(client: client).history(
            symbol: "VWCE.DE", range: HistoryRange(from: "2026-09-14", through: "2026-09-30", monthEndsOnly: true,
                                                   today: today))
        let sent = try #require(await client.requests.first)
        #expect(sent.url.absoluteString == "https://query1.finance.yahoo.com/v8/finance/chart/VWCE.DE"
            + "?period1=1789257600&period2=1790899200&interval=1d&includePrePost=false")
        #expect(history.spacing == .daily)
        #expect(history.quotes.count == 13) // 14 bars, one without a close
        #expect(history.origin == QuoteOrigin(source: .yahoo, service: "Yahoo Finance", symbol: "VWCE.DE"))
        #expect(history.quote(onOrBefore: "2026-09-27") == Quote(price: d("136.88"), currency: .eur,
                                                                 observedOn: "2026-09-25"))
        #expect(history.quote(onOrBefore: "2026-10-01")?.price == d("139.06"))
    }

    @Test func moreThanFiveYearsOfMonthEndsIsOneMonthlyRequest() async throws {
        let client = MockHTTPClient(["chart/GC=F": YahooResponses.goldFuturesMonthly])
        let history = try await YahooChartProvider(client: client).history(
            symbol: "GC=F", range: HistoryRange(from: "2020-12-31", through: "2026-09-30", monthEndsOnly: true,
                                                today: today))
        let sent = try #require(await client.requests.first)
        #expect(sent.url.absoluteString == "https://query1.finance.yahoo.com/v8/finance/chart/GC=F"
            + "?period1=1606694400&period2=1790899200&interval=1mo&includePrePost=false")
        #expect(history.spacing == .monthly)
        #expect(history.quotes.count == 70) // 71 bars; September's twice
        #expect(history.quote(onOrBefore: "2020-12-31")?.price == d("1880.5"))
        #expect(history.quote(onOrBefore: "2021-02-28") == Quote(price: 1734, currency: .usd, observedOn: "2021-02-28"))
        #expect(history.quote(onOrBefore: "2026-08-31")?.price == d("3516.6"))
        // This month's live bar wins over its monthly bar.
        #expect(history.quote(onOrBefore: "2026-09-30")?.price == d("3488.45"))
        #expect(history.quote(onOrBefore: "2026-08-15") == nil)
    }

    @Test func datesThatArentMonthEndsKeepADailyRequest() async throws {
        let client = MockHTTPClient(["chart/": YahooResponses.goldFuturesMonthly])
        _ = try await YahooChartProvider(client: client).history(
            symbol: "GC=F", range: HistoryRange(from: "2020-12-15", through: "2026-09-30", today: today))
        #expect(try #require(await client.requests.first).url.absoluteString.contains("interval=1d"))
        // Nor does a short run of month ends.
        _ = try await YahooChartProvider(client: client).history(
            symbol: "GC=F", range: HistoryRange(from: "2024-12-31", through: "2026-09-30", monthEndsOnly: true,
                                                today: today))
        #expect(await client.requests[1].url.absoluteString.contains("interval=1d"))
    }

    // MARK: Frankfurter

    @Test func aRangeOfRatesIsOneFrankfurterRequest() async throws {
        let client = MockHTTPClient(["2025-06-16..2025-09-01": FrankfurterResponses.weeklySummer2025])
        let history = try await FrankfurterProvider(client: client)
            .rates(base: .eur, quote: .usd, from: "2025-06-16", through: "2025-09-01")
        #expect(try #require(await client.requests.first).url.absoluteString
            == "https://api.frankfurter.dev/v1/2025-06-16..2025-09-01?base=EUR&symbols=USD")
        #expect(history.rates.count == 12)
        #expect(history.isWeekly)
        #expect(history.rate(onOrBefore: "2025-08-31") == FXObservation(rate: d("1.1638"), observedOn: "2025-08-25"))

        let daily = try await FrankfurterProvider(
            client: MockHTTPClient(["frankfurter": PriceResponses.frankfurterUSDSeptember]))
            .rates(base: .eur, quote: .usd, from: "2026-09-16", through: "2026-09-30")
        #expect(!daily.isWeekly)
        #expect(daily.rate(onOrBefore: "2026-09-27")?.rate == d("1.1371"))
    }

    // MARK: gold-api.com

    @Test func aMetalsPastPricesComeFromItsFutures() async throws {
        let client = MockHTTPClient(["chart/GC=F": YahooResponses.goldFuturesMonthly])
        let provider = GoldAPIProvider(client: client)
        let routes = provider.routes(symbol: "xau", today: today)
        #expect(routes.map(\.name) == ["gold-api.com · xau", "Yahoo Finance · GC=F"])
        let history = try await routes[1].fetch(HistoryRange(from: "2020-12-31", through: "2026-09-30",
                                                             monthEndsOnly: true, today: today))
        #expect(history.origin == QuoteOrigin(source: .yahoo, service: "Yahoo Finance", symbol: "GC=F", note: "history"))
        #expect(history.origin?.description == "Yahoo Finance · GC=F (history)")
        #expect(history.quotes.allSatisfy { $0.unit == .troyOunce && $0.currency == .usd })
        #expect(provider.routes(symbol: "XAG", today: today).map(\.name)
            == ["gold-api.com · XAG", "Yahoo Finance · SI=F"])
        // A symbol without futures has only today's spot price.
        #expect(provider.routes(symbol: "XRH", today: today).map(\.name) == ["gold-api.com · XRH"])
    }

    @Test func aSpotPriceCountsForEveryDateItsRouteCovers() {
        let spot = Quote(price: d("3488.45"), currency: .usd, unit: .troyOunce, observedOn: today)
        let history = PriceHistory(quotes: [spot], spacing: .spot)
        #expect(history.quote(onOrBefore: "2026-09-27") == spot)
        #expect(history.quote(onOrBefore: today) == spot)
        #expect(PriceHistory(quotes: [], spacing: .spot).quote(onOrBefore: today) == nil)
    }
}
