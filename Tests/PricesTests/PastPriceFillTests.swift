import Foundation
import Model
@testable import Prices
import Testing
import TestSupport

private func d(_ string: String) -> Decimal { Decimal(fileString: string)! }

/// Filling in past prices with every service answering from recorded (or
/// built) responses in their formats.
struct PastPriceFillTests {
    static let today: CalendarDate = "2026-09-30"

    static func service(_ client: MockHTTPClient) -> PriceService {
        .standard(client: client, policy: PriceServiceTests.generous, today: { today })
    }

    static func instrument(
        _ id: InstrumentID, _ provider: PriceProvider, _ symbol: String, currency: CurrencyCode = .eur,
        unit: InstrumentUnit = .share, kind: InstrumentKind = .etf
    ) -> Instrument {
        Instrument(id: id, name: id.rawValue, kind: kind, currency: currency, unit: unit,
                   assetClasses: .single(.equity), priceSource: PriceSource(provider: provider, symbol: symbol))
    }

    /// Needs for instruments on the given dates, as a library would have them.
    static func needs(_ instruments: [(Instrument, [CalendarDate])]) -> PastPriceNeeds {
        PastPriceNeeds(today: today, baseCurrency: .eur, instruments: instruments.map {
            PastPriceNeeds.InstrumentDates(instrument: $0.0.id, details: $0.0, dates: $0.1)
        })
    }

    /// COMEX gold futures on every weekday of September 2026, in USD per troy
    /// ounce: 3401.23 on Friday the 18th, 3455.10 on Friday the 25th.
    static let goldSeptember = PriceResponses.yahooChart(
        symbol: "GC=F", currency: "USD",
        bars: PriceResponses.weekdays(from: "2026-09-01", through: "2026-09-30").map { day in
            (day, day == "2026-09-18" ? d("3401.23") : day == "2026-09-25" ? d("3455.1") : d("3420"))
        })

    // MARK: Metals

    @Test func metalsComeFromGoldFuturesInEURPerGramAndPerOunce() async throws {
        let client = MockHTTPClient(["chart/GC=F": Self.goldSeptember, "symbols=USD": FrankfurterResponses.september])
        let grams = Self.instrument("coins", .goldAPI, "XAU", unit: .gram, kind: .metal)
        let ounces = Self.instrument("bars", .goldAPI, "XAU", unit: .troyOunce, kind: .metal)
        let dates: [CalendarDate] = ["2026-09-18", "2026-09-27"]
        let fill = await Self.service(client).fillPastPrices(Self.needs([(grams, dates), (ounces, dates)]),
                                                             in: Library())

        // 3,401.23 USD per ounce at 1 EUR = 1.1349 USD is 96.3539 EUR per
        // gram; Sunday the 27th takes Friday's close and rate.
        #expect(fill.prices == [
            PriceRecord(instrument: "bars", date: "2026-09-18", price: d("2996.94"), currency: .eur, source: .yahoo),
            PriceRecord(instrument: "coins", date: "2026-09-18", price: d("96.3539"), currency: .eur, source: .yahoo),
            PriceRecord(instrument: "bars", date: "2026-09-27", price: d("3038.52"), currency: .eur, source: .yahoo),
            PriceRecord(instrument: "coins", date: "2026-09-27", price: d("97.6907"), currency: .eur, source: .yahoo),
        ])
        // The rates that converted them are recorded too.
        #expect(fill.fx == [
            FXRecord(base: .eur, quote: .usd, date: "2026-09-18", rate: d("1.1349"), source: .ecb),
            FXRecord(base: .eur, quote: .usd, date: "2026-09-27", rate: d("1.1371"), source: .ecb),
        ])
        let coins = try #require(fill.result(for: .instrument("coins")))
        #expect(coins.status == .filled)
        #expect(coins.sources == [PastPriceSource(
            origin: QuoteOrigin(source: .yahoo, service: "Yahoo Finance", symbol: "GC=F", note: "history"),
            first: "2026-09-18", last: "2026-09-27", count: 2)])
        // One request for both instruments' gold, one for the rates.
        #expect(await client.requests(matching: "chart/GC=F").count == 1)
        #expect(await client.requests(matching: "frankfurter").count == 1)
        #expect(try #require(await client.requests(matching: "chart/GC=F").first).url.absoluteString
            .contains("period1=1788998400&period2=1790640000&interval=1d"))
    }

    @Test func aPastCheckInGetsGoldFromItsFutures() async throws {
        let june = PriceResponses.yahooChart(
            symbol: "GC=F", currency: "USD",
            bars: PriceResponses.weekdays(from: "2026-06-22", through: "2026-06-30").map { ($0, d("3483.37")) })
        let client = MockHTTPClient([
            "chart/GC=F": june,
            "2026-06-16..2026-06-30": """
            {"amount":1.0,"base":"EUR","start_date":"2026-06-16","end_date":"2026-06-30","rates":{\
            "2026-06-26":{"USD":1.1288},"2026-06-29":{"USD":1.1294},"2026-06-30":{"USD":1.1301}}}
            """,
            "prc_hicp_minr": EurostatResponses.hicpITJulyToSeptember,
        ])
        var library = Library(
            accounts: [Account(id: "safe", name: "Safe", kind: .metals, currency: .eur, opened: "2020-01-01")],
            instruments: [Self.instrument("gold", .goldAPI, "XAU", unit: .gram, kind: .metal)])
        library.upsert(Valuation(account: "safe", date: "2026-05-31", positions: [Position(instrument: "gold", quantity: 50)]))

        let result = await Self.service(client).fetch(for: library, on: "2026-06-30")
        #expect(result.isComplete)
        #expect(result.prices == [PriceRecord(instrument: "gold", date: "2026-06-30", price: d("99.1"), currency: .eur,
                                              source: .yahoo)])
        let entry = try #require(result.entry(for: .instrument("gold")))
        #expect(entry.source == .yahoo)
        #expect(entry.symbol == "GC=F")
        #expect(entry.note == "history")
        #expect(entry.details?.observedOn == "2026-06-30")
        #expect(entry.details?.quote?.unit == .troyOunce)
        // gold-api.com isn't asked: it only has today's price.
        #expect(await client.requests(matching: "gold-api").isEmpty)
    }

    // MARK: Requests

    @Test func eachInstrumentsWholeRangeIsOneRequest() async throws {
        let closes = PriceResponses.yahooChart(
            symbol: "VWCE.DE", currency: "EUR", exchangeName: "GER", instrumentType: "ETF", timeZone: "Europe/Berlin",
            hour: 9, bars: PriceResponses.weekdays(from: "2025-10-20", through: "2026-09-30").map { ($0, d("130")) })
        let client = MockHTTPClient(["chart/VWCE.DE": closes])
        let monthEnds = (0..<12).map { YearMonth(year: 2025, month: 10)!.adding(months: $0).lastDay }
        // Two instruments on the same listing share the request.
        let fill = await Self.service(client).fillPastPrices(Self.needs([
            (Self.instrument("vwce", .yahoo, "VWCE.DE"), monthEnds),
            (Self.instrument("vwce-gift", .yahoo, "VWCE.DE"), Array(monthEnds.suffix(3))),
        ]), in: Library())
        #expect(fill.prices.count == 15)
        #expect(fill.prices.allSatisfy { $0.price == 130 && $0.source == .yahoo })
        let requests = await client.requests
        #expect(requests.count == 1)
        // From a week before the first month end, a day earlier for exchanges east of UTC.
        #expect(try #require(requests.first).url.absoluteString == "https://query1.finance.yahoo.com/v8/finance/chart/"
            + "VWCE.DE?period1=1761177600&period2=1790899200&interval=1d&includePrePost=false")
        #expect(fill.result(for: .instrument("vwce"))?.sources.map(\.origin.description) == ["Yahoo Finance · VWCE.DE"])
    }

    // MARK: Crypto

    /// A coin's prices every day at 00:00 UTC, as Yahoo lists crypto pairs.
    static func pair(_ symbol: String, currency: String, from: CalendarDate, through: CalendarDate,
                     priceHint: Int = 2, _ close: (CalendarDate) -> Decimal) -> String {
        var days: [CalendarDate] = []
        var day = from
        while day <= through {
            days.append(day)
            day = day.adding(days: 1)
        }
        return PriceResponses.yahooChart(symbol: symbol, currency: currency, exchangeName: "CCC",
                                         instrumentType: "CRYPTOCURRENCY", timeZone: "UTC", priceHint: priceHint,
                                         bars: days.map { ($0, close($0)) })
    }

    @Test func cryptoOlderThanCoinGeckosYearComesFromYahoosPairInItsCurrency() async throws {
        let recent = PriceResponses.coinGeckoMarketChart(
            (0...10).map { (PriceResponses.midnightUTC(CalendarDate("2026-09-20").adding(days: $0)), d("3790.12")) }
                + [(PriceResponses.midnightUTC("2026-09-30").addingTimeInterval(9 * 3600), d("3812.0625"))])
        let client = MockHTTPClient([
            "market_chart/range": recent,
            "chart/ETH-EUR": Self.pair("ETH-EUR", currency: "EUR", from: "2025-06-23", through: "2025-09-01") {
                $0 == "2025-06-30" ? d("2310.55") : $0 == "2025-08-31" ? d("3950.2") : d("3000")
            },
        ])
        let eth = Self.instrument("eth", .coingecko, "ETH", unit: "ETH", kind: .crypto)
        let fill = await Self.service(client).fillPastPrices(
            Self.needs([(eth, ["2025-06-30", "2025-08-31", "2026-09-27", "2026-09-30"])]), in: Library())

        #expect(fill.prices == [
            PriceRecord(instrument: "eth", date: "2025-06-30", price: d("2310.55"), currency: .eur, source: .yahoo),
            PriceRecord(instrument: "eth", date: "2025-08-31", price: d("3950.2"), currency: .eur, source: .yahoo),
            PriceRecord(instrument: "eth", date: "2026-09-27", price: d("3790.12"), currency: .eur, source: .coingecko),
            PriceRecord(instrument: "eth", date: "2026-09-30", price: d("3812.0625"), currency: .eur, source: .coingecko),
        ])
        let result = try #require(fill.result(for: .instrument("eth")))
        #expect(result.status == .filled)
        // Which source filled which dates.
        #expect(result.sources == [
            PastPriceSource(origin: QuoteOrigin(source: .yahoo, service: "Yahoo Finance", symbol: "ETH-EUR",
                                                note: "history"),
                            first: "2025-06-30", last: "2025-08-31", count: 2),
            PastPriceSource(origin: QuoteOrigin(source: .coingecko, service: "CoinGecko", symbol: "ethereum"),
                            first: "2026-09-27", last: "2026-09-30", count: 2),
        ])
        // CoinGecko is only asked for its year; Yahoo for the rest.
        #expect(try #require(await client.requests(matching: "market_chart").first).url.absoluteString
            .contains("from=1789862400&"))
        #expect(await client.requests(matching: "chart/ETH-EUR").count == 1)
        #expect(await client.requests(matching: "ETH-USD").isEmpty)
    }

    @Test func aCoinKnownByItsIDWithoutAPairInTheCurrencyUsesTheDollarPair() async throws {
        let client = MockHTTPClient()
        await client.on("search?query=moonstone", json: CoinGeckoResponses.searchMoonstone)
        await client.on("chart/MOON-EUR", HTTPResponse(statusCode: 404, text: YahooResponses.notFound))
        await client.on("chart/MOON-USD", json: Self.pair("MOON-USD", currency: "USD", from: "2025-06-23",
                                                          through: "2025-09-01", priceHint: 4) {
            $0 == "2025-06-30" ? d("0.5123") : $0 == "2025-08-31" ? d("0.4876") : d("0.5")
        })
        await client.on("symbols=USD", json: FrankfurterResponses.weeklySummer2025)
        let moon = Self.instrument("moon", .coingecko, "moonstone", unit: "MOON", kind: .crypto)
        let fill = await Self.service(client).fillPastPrices(Self.needs([(moon, ["2025-06-30", "2025-08-31"])]),
                                                             in: Library())

        // 0.5123 USD at 1 EUR = 1.1747 USD; Sunday 31 August takes the week's rate.
        #expect(fill.prices == [
            PriceRecord(instrument: "moon", date: "2025-06-30", price: d("0.436111"), currency: .eur, source: .yahoo),
            PriceRecord(instrument: "moon", date: "2025-08-31", price: d("0.418972"), currency: .eur, source: .yahoo),
        ])
        #expect(fill.fx.map(\.rate) == [d("1.1747"), d("1.1638")])
        #expect(fill.result(for: .fx(base: .eur, quote: .usd))?.observedOn == [
            "2025-06-30": "2025-06-30", "2025-08-31": "2025-08-25",
        ])
        #expect(fill.result(for: .instrument("moon"))?.sources.map(\.origin.description)
            == ["Yahoo Finance · MOON-USD (history)"])
        // CoinGecko's search named the coin's ticker; its prices weren't asked for.
        #expect(await client.requests(matching: "search?query=moonstone").count == 1)
        #expect(await client.requests(matching: "market_chart").isEmpty)
        #expect(await client.requests(matching: "frankfurter").count == 1)
    }

    @Test func cryptoWithoutHistoryAnywhereIsReportedNotSkipped() async throws {
        let client = MockHTTPClient()
        await client.on("market_chart/range", json: PriceResponses.coinGeckoMarketChart(
            [(PriceResponses.midnightUTC("2026-09-30"), d("0.39"))]))
        await client.on("search?query=moonstone", json: CoinGeckoResponses.searchMoonstone)
        await client.on("chart/MOON-", HTTPResponse(statusCode: 404, text: YahooResponses.notFound))
        let moon = Self.instrument("moon", .coingecko, "moonstone", unit: "MOON", kind: .crypto)
        let fill = await Self.service(client).fillPastPrices(Self.needs([(moon, ["2025-06-30", "2026-09-29"])]),
                                                             in: Library())

        let result = try #require(fill.result(for: .instrument("moon")))
        #expect(result.status == .partlyFilled)
        #expect(result.filled == ["2026-09-29"])
        #expect(result.missing == ["2025-06-30"])
        #expect(result.reason == "CoinGecko's free API only has prices for the last 365 days. "
            + "Yahoo Finance doesn't know \"MOON-EUR\": No data found, symbol may be delisted. "
            + "Yahoo Finance doesn't know \"MOON-USD\": No data found, symbol may be delisted.")
    }

    // MARK: Nothing silent

    @Test func instrumentsWithoutAHistoryAreListedWithTheirDatesAndWhy() async throws {
        let client = MockHTTPClient()
        var needs = Self.needs([
            (Self.instrument("rhodium", .goldAPI, "XRH", unit: .gram, kind: .metal), ["2026-08-31", "2026-09-30"]),
            (Self.instrument("us-stock", .eodhd, "AAPL.US"), ["2026-09-30"]),
        ])
        let fund = Instrument(id: "fund", name: "Private fund", kind: .fund, currency: .eur, unit: .share,
                              assetClasses: .single(.equity))
        needs.manualInstruments = [PastPriceNeeds.InstrumentDates(instrument: "fund", details: fund,
                                                                  dates: ["2026-06-30", "2026-07-31", "2026-08-31"])]
        needs.unknownInstruments = [PastPriceNeeds.InstrumentDates(instrument: "mystery", details: nil,
                                                                   dates: ["2026-09-30"])]
        let fill = await Self.service(client).fillPastPrices(needs, in: Library())

        #expect(fill.prices.isEmpty)
        #expect(await client.requestCount == 0)
        #expect(fill.results.map(\.item) == [
            .instrument("rhodium"), .instrument("us-stock"), .instrument("fund"), .instrument("mystery"),
        ])
        let rhodium = try #require(fill.result(for: .instrument("rhodium")))
        #expect(rhodium.status == .notFilled)
        #expect(rhodium.missing == ["2026-08-31", "2026-09-30"])
        #expect(rhodium.reason == "gold-api.com has no price history for XRH: type the prices in, "
            + "or choose a price source that has one.")
        #expect(fill.result(for: .instrument("us-stock"))?.reason
            == "There's no \"eodhd\" price provider yet. Enter the price by hand.")
        let manual = try #require(fill.result(for: .instrument("fund")))
        #expect(manual.status == .manual)
        #expect(manual.missing == ["2026-06-30", "2026-07-31", "2026-08-31"])
        #expect(manual.reason == "It has no price source. Type its prices in, or choose a source to fetch them from.")
        #expect(fill.result(for: .instrument("mystery"))?.status == .unknownInstrument)
    }

    // MARK: Saving

    @Test func existingRecordsAreNeverReplaced() async throws {
        var library = PastPriceNeedsTests.library()
        for date: CalendarDate in ["2026-07-31", "2026-08-31", "2026-09-30"] {
            library.upsert(Valuation(account: "broker", date: date, positions: [Position(instrument: "vwce", quantity: 10)]))
        }
        library.upsert(PriceRecord(instrument: "vwce", date: "2026-07-31", price: 120, currency: .eur, source: .manual))
        library.upsert(PriceRecord(instrument: "vwce", date: "2026-08-31", price: 121, currency: .eur, source: .ledger))
        let closes = PriceResponses.yahooChart(
            symbol: "VWCE.DE", currency: "EUR", exchangeName: "GER", instrumentType: "ETF", timeZone: "Europe/Berlin",
            hour: 9, bars: PriceResponses.weekdays(from: "2026-09-01", through: "2026-09-30").map { ($0, d("138.42")) })
        let client = MockHTTPClient(["chart/VWCE.DE": closes])
        let service = Self.service(client)
        let needs = service.pastPriceNeeds(for: library)
        #expect(needs.dates(for: "vwce") == ["2026-09-30"])
        let fill = await service.fillPastPrices(needs, in: library)
        #expect(fill.prices == [PriceRecord(instrument: "vwce", date: "2026-09-30", price: d("138.42"), currency: .eur,
                                            source: .yahoo)])

        // A price typed in on another device meanwhile stays.
        var changed = library
        changed.upsert(PriceRecord(instrument: "vwce", date: "2026-09-30", price: 140, currency: .eur, source: .manual))
        let kept = fill.insertMissing(into: &changed)
        #expect(kept.added == 0 && kept.kept == 1)
        #expect(changed.prices(for: "vwce").map(\.price) == [120, 121, 140])
        #expect(changed.prices(for: "vwce").map(\.source) == [.manual, .ledger, .manual])

        let added = fill.insertMissing(into: &library)
        #expect(added.prices == 1 && added.kept == 0)
        #expect(library.prices(for: "vwce").map(\.source) == [.manual, .ledger, .yahoo])
        // An FX rate recorded the other way round counts as there.
        var rates = Library()
        rates.upsert(FXRecord(base: .usd, quote: .eur, date: "2026-09-30", rate: d("0.88")))
        let fx = PastPriceFill(fx: [FXRecord(base: .eur, quote: .usd, date: "2026-09-30", rate: d("1.1398"))])
            .insertMissing(into: &rates)
        #expect(fx.kept == 1 && rates.allFXRates.count == 1)
    }

    // MARK: End to end

    /// The example library's gold prices, as COMEX closes: at each month's
    /// last trading day, the price in USD per ounce that gives the library's
    /// EUR per gram at its EUR/USD rate. Other days are a little lower.
    static let exampleGoldCloses: [CalendarDate: Decimal] = [
        "2025-10-31": d("3108.7"), "2025-11-28": d("3169.72"), "2025-12-31": d("3253.31"), "2026-01-30": d("3322.13"),
        "2026-02-27": d("3271.56"), "2026-03-31": d("3359.87"), "2026-04-30": d("3427.15"), "2026-05-29": d("3415.77"),
        "2026-06-30": d("3483.37"), "2026-07-31": d("3515.01"), "2026-08-31": d("3516.55"), "2026-09-30": d("3488.45"),
    ]

    static var exampleGoldChart: String {
        PriceResponses.yahooChart(
            symbol: "GC=F", currency: "USD",
            bars: PriceResponses.weekdays(from: "2025-10-20", through: "2026-09-30", except: ["2025-12-25"]).map { day in
                (day, exampleGoldCloses[day] ?? d("3000"))
            })
    }

    @Test func theExampleLibraryWithoutGoldPricesIsFilledEndToEnd() async throws {
        let original = try Fixtures.exampleLibrary()
        var library = original
        for month in library.months.keys { library.months[month]?.prices.removeAll { $0.instrument == "gold" } }
        let client = MockHTTPClient([
            "chart/GC=F": Self.exampleGoldChart, "prc_hicp_minr": EurostatResponses.hicpITJulyToSeptember,
        ])
        let service = Self.service(client)
        let needs = service.pastPriceNeeds(for: library)
        #expect(needs.priceCount == 12)
        let events = ProgressLog()
        let fill = await service.fillPastPrices(needs, in: library) { await events.add($0) }

        // The library's own prices again (to the sixth digit), now from Yahoo
        // Finance's gold futures, converted at the library's EUR/USD rates.
        let expected: [String] = ["92.1001", "93.4001", "95.2001", "96.7999", "95.9", "97.2999", "98.5999", "97.7999",
                                  "99.1", "100.4", "99.6999", "98.4"]
        #expect(fill.prices.map(\.price) == expected.map(d))
        #expect(fill.prices.map(\.date) == original.prices(for: "gold").map(\.date))
        #expect(fill.prices.allSatisfy { $0.instrument == "gold" && $0.currency == .eur && $0.source == .yahoo })
        #expect(fill.fx.isEmpty) // The library has the rates.
        #expect(fill.indices.isEmpty) // September's inflation isn't out yet.
        let gold = try #require(fill.result(for: .instrument("gold")))
        #expect(gold.status == .filled)
        #expect(gold.sources.map(\.origin.description) == ["Yahoo Finance · GC=F (history)"])
        #expect(gold.sources.first?.count == 12)
        // The day each value is from: Friday's close for a Sunday month end.
        #expect(gold.observedOn["2025-11-30"] == "2025-11-28")
        #expect(gold.observedOn["2026-09-30"] == "2026-09-30")
        #expect(gold.observedOn.count == 12)
        let hicp = try #require(fill.result(for: .index(.hicpIT)))
        #expect(hicp.missing == ["2026-09-30"])
        #expect(hicp.reason == "Eurostat has no value for 1 month (the latest months may not be published yet).")
        // One request for a year of gold, one for inflation.
        #expect(await client.requestCount == 2)
        let progress = await events.all
        #expect(progress.map(\.done) == [1, 2])
        #expect(progress.last?.total == 2)

        let added = fill.insertMissing(into: &library)
        #expect(added.prices == 12)
        #expect(library.prices(for: "gold").map(\.date) == original.prices(for: "gold").map(\.date))
        #expect(service.pastPriceNeeds(for: library).instruments.isEmpty)
    }
}

/// Progress events, in the order they arrived.
actor ProgressLog {
    private(set) var all: [PastPriceProgress] = []

    func add(_ event: PastPriceProgress) {
        all.append(event)
    }
}
