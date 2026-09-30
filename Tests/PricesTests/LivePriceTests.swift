import Foundation
import Model
import Prices
import Testing
import TestSupport

/// Smoke tests against the real APIs. They run only with
/// `LIVE_PRICE_TESTS=1 swift test --filter LivePriceTests`, and read an
/// optional CoinGecko demo key from `COINGECKO_API_KEY`. The history tests
/// check each ranged request, that gold futures track the spot price, that a
/// monthly Yahoo bar closes at the month's last daily close, and a fill of
/// the example library's gold.
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

    // MARK: History

    /// The last day of the month before this one.
    private var lastMonthEnd: CalendarDate { today.startOfMonth.adding(days: -1) }

    @Test func eachProviderAnswersARange() async throws {
        // Yahoo Finance, daily: two months of an ETF.
        let range = HistoryRange(from: today.adding(days: -60), through: today, today: today)
        let vwce = try await YahooChartProvider().history(symbol: "VWCE.DE", range: range)
        #expect(vwce.spacing == .daily && vwce.quotes.count > 30)
        #expect(vwce.quote(onOrBefore: lastMonthEnd) != nil)

        // Frankfurter: two years of rates in one request.
        let rates = try await FrankfurterProvider()
            .rates(base: .eur, quote: .usd, from: today.adding(years: -2), through: today)
        #expect(rates.rate(onOrBefore: today.adding(years: -1)) != nil)
        #expect(rates.rate(onOrBefore: lastMonthEnd) != nil)
        print("Frankfurter: \(rates.rates.count) rates over two years, \(rates.isWeekly ? "weekly" : "daily")")

        // CoinGecko: its free year, and nothing asked before it.
        let coinGecko = CoinGeckoProvider(credentials: credentials)
        let btc = try await coinGecko.history(
            symbol: "bitcoin", currency: .eur,
            range: HistoryRange(from: today.adding(days: -200), through: today, today: today))
        #expect(btc.quotes.count > 150)
        #expect(btc.quote(onOrBefore: lastMonthEnd).map { $0.price > 1000 } == true)

        // Yahoo Finance's crypto pairs, for older dates.
        let old = HistoryRange(from: today.adding(years: -3), through: today.adding(years: -2), today: today)
        let btcEUR = try await YahooChartProvider().history(symbol: "BTC-EUR", range: old)
        #expect(btcEUR.quotes.count > 300)
        #expect(btcEUR.quotes.allSatisfy { $0.currency == .eur })
    }

    @Test func goldFuturesTrackSpotAndMonthlyBarsCloseTheMonth() async throws {
        let spot = try await GoldAPIProvider()
            .quote(for: QuoteRequest(symbol: "XAU", date: today, currency: .usd, today: today))
        let yahoo = YahooChartProvider()
        let daily = try await yahoo.history(
            symbol: "GC=F", range: HistoryRange(from: today.adding(days: -45), through: today, today: today))
        let latest = try #require(daily.quotes.last)
        // Futures trade within about 1% of spot (a little above, for carry).
        let gap = abs((latest.price - spot.price) / spot.price)
        #expect(gap < Decimal(string: "0.03")!, "GC=F \(latest.price) vs spot \(spot.price)")
        print("GC=F \(latest.price) on \(latest.observedOn) vs gold-api.com spot \(spot.price): \(gap * 100)%")

        // A monthly bar's close is the month's last daily close.
        let monthly = try await yahoo.history(
            symbol: "GC=F", range: HistoryRange(from: today.adding(years: -6), through: lastMonthEnd,
                                                monthEndsOnly: true, today: today))
        #expect(monthly.spacing == .monthly && monthly.quotes.count >= 70)
        let monthEnd = try #require(monthly.quote(onOrBefore: lastMonthEnd))
        let dayClose = try #require(daily.quote(onOrBefore: lastMonthEnd))
        #expect(monthEnd.price == dayClose.price, "monthly \(monthEnd.price), daily \(dayClose.price)")
    }

    @Test func theExampleLibrarysGoldIsFilledIn() async throws {
        var library = try Fixtures.exampleLibrary()
        for month in library.months.keys { library.months[month]?.prices.removeAll { $0.instrument == "gold" } }
        let service = PriceService.standard(credentials: credentials)
        let needs = service.pastPriceNeeds(for: library)
        let fill = await service.fillPastPrices(needs, in: library)
        let gold = try #require(fill.result(for: .instrument("gold")))
        #expect(gold.status == .filled, "\(gold.reason ?? "")")
        #expect(gold.sources.map(\.origin.symbol) == ["GC=F"])
        // Plausible euros per gram.
        for price in fill.prices {
            print("gold \(price.date): \(price.price) EUR/g")
            #expect(price.price > 50 && price.price < 250)
        }
    }
}
