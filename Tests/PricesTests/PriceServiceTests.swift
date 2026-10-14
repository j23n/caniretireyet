import Foundation
import Model
@testable import Prices
import Testing
import TestSupport

/// The price service over the made-up example library, with every provider
/// answering from recorded responses.
struct PriceServiceTests {
    static let checkIn: CalendarDate = "2026-09-30"

    /// A client that answers every request a check-in on 2026-09-30 makes.
    static func client() -> MockHTTPClient {
        MockHTTPClient([
            "symbols=USD": PriceResponses.frankfurterUSDSeptember,
            "symbols=CHF": FrankfurterResponses.septemberCHF,
            "chart/BTC-USD": PriceResponses.yahooBitcoinSeptember,
            "price/XAU": PriceResponses.goldAPIGold,
            "chart/VWCE.DE": PriceResponses.yahooVWCESeptember,
            "prc_hicp_minr": PriceResponses.eurostatHICPItaly,
        ])
    }

    /// The standard policy with a generous timeout: the recorded responses
    /// answer at once, but a busy test machine can delay them by seconds,
    /// and these tests aren't about timeouts.
    static let generous = RequestPolicy(timeout: .seconds(60))

    static func service(_ client: MockHTTPClient, policy: RequestPolicy = generous) -> PriceService {
        .standard(client: client, policy: policy, today: { checkIn })
    }

    /// The example library with bitcoin priced from Yahoo Finance's
    /// `BTC-USD` pair, and its recorded prices from there too.
    static func exampleLibrary() throws -> Library {
        var library = try Self.exampleLibrary()
        library.instruments["btc"]?.priceSource = PriceSource(provider: .yahoo, symbol: "BTC-USD")
        for month in library.months.keys {
            library.months[month]?.prices = (library.months[month]?.prices ?? []).map { price in
                var price = price
                if price.instrument == "btc" { price.source = .yahoo }
                return price
            }
        }
        return library
    }

    @Test func fetchesWhatTheExampleLibraryNeeds() async throws {
        let library = try Self.exampleLibrary()
        let client = Self.client()
        let result = await Self.service(client).fetch(for: library, on: Self.checkIn)

        #expect(result.isComplete)
        // The same records the example library holds for its September check-in.
        let september = try #require(library.months["2026-09"])
        #expect(result.prices == september.prices)
        #expect(result.fx == september.fx)
        #expect(result.indices.isEmpty)
        #expect(result.results.map(\.item) == [
            .instrument("btc"), .instrument("gold"), .instrument("vwce"), .fx(base: .eur, quote: .usd), .index(.hicpIT),
        ])
        #expect(result.result(for: .instrument("btc"))?.shownOrigin?.description == "Yahoo Finance · BTC-USD")

        // Gold: 3,488.45 USD per troy ounce at 1 EUR = 1.1398 USD is 98.4 EUR per gram.
        let gold = try #require(result.result(for: .instrument("gold")))
        let goldAPI = QuoteOrigin(source: .goldAPI, service: "gold-api.com", symbol: "XAU")
        #expect(gold.status == .filled)
        #expect(gold.origin == goldAPI)
        #expect(gold.shownOrigin == goldAPI)
        #expect(gold.quotes[Self.checkIn] == Quote(price: d("3488.45"), currency: .usd, unit: .troyOunce,
                                                   observedOn: Self.checkIn, origin: goldAPI))
        // Italy's HICP for September isn't out yet; August is the latest.
        let hicp = try #require(result.result(for: .index(.hicpIT)))
        #expect(hicp.asOf == "2026-08-31")
        #expect(hicp.status == .notFilled && !hicp.isFailure)

        // One request per item: the EUR/USD rate is shared by the FX entry
        // and the gold conversion.
        #expect(await client.requestCount == 5)
        #expect(await client.requests(matching: "frankfurter").count == 1)
    }

    /// The app's price-source picker offers `standardInstrumentProviders`,
    /// so it must name exactly the providers the standard service registers.
    @Test func standardInstrumentProvidersAreTheRegisteredOnes() {
        let service = Self.service(Self.client())
        #expect(Set(service.instrumentProviders.keys) == Set(PriceService.standardInstrumentProviders))
        #expect(PriceService.standardInstrumentProviders.count == service.instrumentProviders.count)
        #expect(!PriceService.standardInstrumentProviders.contains(.eodhd))
        #expect(!PriceService.standardInstrumentProviders.contains(.twelveData))
    }

    @Test func reopeningACheckInUsesTheCache() async throws {
        let library = try Self.exampleLibrary()
        let client = Self.client()
        let service = Self.service(client)

        let first = await service.fetch(for: library, on: Self.checkIn)
        #expect(await client.requestCount == 5)
        let second = await service.fetch(for: library, on: Self.checkIn)
        #expect(await client.requestCount == 5)
        #expect(second == first)
        // A week back for a weekend or holiday; only a month end is wanted.
        #expect(await service.cache.contains("Yahoo Finance · VWCE.DE 2026-09-23..2026-09-30 month ends"))

        _ = await service.fetch(for: library, on: Self.checkIn, refresh: true)
        #expect(await client.requestCount == 10)
    }

    /// Crypto was once priced from CoinGecko. An instrument whose source
    /// still says so has its prices typed in, and nothing is asked for it.
    @Test func aCoinGeckoSourceIsTypedIn() async throws {
        var library = try Self.exampleLibrary()
        library.instruments["btc"]?.priceSource = PriceSource(provider: "coingecko", symbol: "bitcoin")
        let client = Self.client()
        let result = await Self.service(client).fetch(for: library, on: Self.checkIn)

        #expect(result.isComplete)
        #expect(result.result(for: .instrument("btc"))?.status == .manual)
        #expect(result.prices.map(\.instrument) == ["gold", "vwce"])
        #expect(await client.requests(matching: "BTC").isEmpty)
        #expect(await client.requestCount == 4)
    }

    @Test func missingIndexMonthsAreFilledIn() async throws {
        var library = try Self.exampleLibrary()
        library.months["2026-07"]?.indices = []
        library.months["2026-08"]?.indices = []
        let result = await Self.service(Self.client()).fetch(for: library, on: Self.checkIn)
        #expect(result.indices == [
            IndexRecord(index: .hicpIT, date: "2026-07-31", value: d("128.1"), source: .eurostat),
            IndexRecord(index: .hicpIT, date: "2026-08-31", value: d("128.41"), source: .eurostat),
        ])

        let merge = result.merge(into: &library, policy: .replaceFetched)
        #expect(merge.indices == 2 && merge.prices == 0 && merge.identical == 4)
        #expect(library.months["2026-08"]?.indices.first?.value == d("128.41"))
        #expect(library.months["2026-09"]?.prices.count == 3)
    }

    @Test func aWeekendCheckInRecordsFridaysValuesOnItsOwnDate() async throws {
        let library = try Self.exampleLibrary()
        let sunday: CalendarDate = "2026-09-27"
        let result = await Self.service(Self.client()).fetch(for: library, on: sunday)
        #expect(result.prices.first { $0.instrument == "vwce" }
            == PriceRecord(instrument: "vwce", date: sunday, price: d("136.88"), currency: .eur, source: .yahoo))
        #expect(result.fx == [FXRecord(base: .eur, quote: .usd, date: sunday, rate: d("1.1371"), source: .ecb)])
        #expect(result.result(for: .instrument("vwce"))?.observedOn[sunday] == "2026-09-25")
        #expect(result.result(for: .fx(base: .eur, quote: .usd))?.observedOn[sunday] == "2026-09-25")
        // gold-api.com's spot price counts for the last three days.
        #expect(result.result(for: .instrument("gold"))?.observedOn[sunday] == Self.checkIn)
    }

    @Test func oneFailureDoesntStopTheRest() async throws {
        let client = MockHTTPClient()
        await client.on("chart/VWCE.DE", HTTPResponse(statusCode: 500, text: "Internal Server Error"))
        await client.on("chart/BTC-USD", HTTPResponse(statusCode: 429, headers: ["Retry-After": "120"],
                                                      text: "Too Many Requests"))
        await client.on("symbols=USD", json: PriceResponses.frankfurterUSDSeptember)
        await client.on("price/XAU", json: PriceResponses.goldAPIGold)
        await client.on("prc_hicp_minr", json: PriceResponses.eurostatHICPItaly)

        let result = await Self.service(client).fetch(for: try Self.exampleLibrary(), on: Self.checkIn)
        #expect(!result.isComplete)
        #expect(result.prices.map(\.instrument) == ["gold"])
        #expect(result.fx.count == 1)
        #expect(result.failures.map(\.item) == [.instrument("btc"), .instrument("vwce")])
        #expect(result.result(for: .instrument("vwce"))?.failureReason
            == "Yahoo Finance answered with HTTP 500: Internal Server Error.")
        #expect(result.result(for: .instrument("btc"))?.failureReason
            == "Yahoo Finance is limiting requests. Try again in 120 seconds.")
    }

    /// Yahoo never answers and times out after 200 ms; everything else
    /// still arrives. Only Yahoo gets the short timeout, and bitcoin's price
    /// is typed in, so nothing else can time out on a busy machine. (The
    /// time limit only guards against a hang.)
    @Test(.timeLimit(.minutes(1)))
    func aSlowProviderTimesOutAlone() async throws {
        let client = Self.client()
        await client.on("chart/SLOW", HTTPResponse(statusCode: 200, text: PriceResponses.yahooVWCESeptember),
                        delay: MockHTTPClient.never)
        var library = try Self.exampleLibrary()
        library.instruments["vwce"]?.priceSource = PriceSource(provider: .yahoo, symbol: "SLOW")
        library.instruments["btc"]?.priceSource = nil
        let service = PriceService(
            instrumentProviders: [
                YahooChartProvider(client: client, policy: RequestPolicy(timeout: .milliseconds(200))),
                GoldAPIProvider(client: client, policy: Self.generous),
            ],
            fxProvider: FrankfurterProvider(client: client, policy: Self.generous),
            makeIndexProvider: { EurostatIndexProvider(index: $0, client: client, policy: Self.generous) },
            today: { Self.checkIn })

        let result = await service.fetch(for: library, on: Self.checkIn)
        #expect(result.failures.map(\.item) == [.instrument("vwce")])
        #expect(result.result(for: .instrument("vwce"))?.failureReason
            == "Yahoo Finance didn't answer within 200 ms.")
        #expect(result.prices.map(\.instrument) == ["gold"])
        #expect(result.fx.map(\.quote) == [.usd])
        #expect(result.result(for: .index(.hicpIT))?.failureReason == nil)
    }

    @Test func withoutAnFXRateTheGoldPriceCantBeConverted() async throws {
        let client = MockHTTPClient()
        await client.on("frankfurter", HTTPResponse(statusCode: 503, text: "Service Unavailable"))
        await client.on("chart/BTC-USD", json: PriceResponses.yahooBitcoinSeptember)
        await client.on("price/XAU", json: PriceResponses.goldAPIGold)
        await client.on("chart/VWCE.DE", json: PriceResponses.yahooVWCESeptember)
        await client.on("prc_hicp_minr", json: PriceResponses.eurostatHICPItaly)
        // Without the rate the library has for the day, which would be used.
        var library = try Self.exampleLibrary()
        library.months["2026-09"]?.fx = []

        let result = await Self.service(client).fetch(for: library, on: Self.checkIn)
        #expect(result.fx.isEmpty)
        // btc is priced in USD, as Yahoo Finance quotes it: no conversion needed.
        #expect(result.prices.map(\.instrument) == ["btc", "vwce"])
        #expect(result.failures.map(\.item) == [.instrument("gold"), .fx(base: .eur, quote: .usd)])
        #expect(result.result(for: .instrument("gold"))?.failureReason
            == "No USD→EUR rate to convert the price: Frankfurter (ECB) answered with HTTP 503: Service Unavailable.")
    }

    /// A rate the library has for the day converts a price without a request.
    @Test func theLibrarysRateConvertsAPrice() async throws {
        let client = Self.client()
        let library = try Self.exampleLibrary()
        let result = await Self.service(client).fetch(
            PriceNeeds(library: library, checkInOn: Self.checkIn, indices: []).withoutRates, in: library)
        #expect(result.prices.first { $0.instrument == "gold" }?.price == d("98.4"))
        #expect(result.fx.isEmpty)
        #expect(await client.requests(matching: "frankfurter").isEmpty)
    }

    @Test func quotesInAnotherCurrencyConvertThroughTheBase() async throws {
        let client = Self.client()
        let usdChart = PriceResponses.yahooVWCESeptember
            .replacingOccurrences(of: #""currency":"EUR""#, with: #""currency":"USD""#)
        await client.on("chart/SPY", json: usdChart)
        var library = Library(
            accounts: [Account(id: "broker", name: "Broker", kind: .brokerage, currency: .chf, opened: "2024-01-01")],
            instruments: [
                Instrument(id: "spy-eur", name: "In EUR", kind: .etf, currency: .eur, unit: .share,
                           assetClasses: .single(.equity), priceSource: PriceSource(provider: .yahoo, symbol: "SPY")),
                Instrument(id: "spy-chf", name: "In CHF", kind: .etf, currency: .chf, unit: .share,
                           assetClasses: .single(.equity), priceSource: PriceSource(provider: .yahoo, symbol: "SPY")),
            ])
        library.upsert(Trade(account: "broker", date: "2026-08-31", id: "a", type: .opening, instrument: "spy-eur",
                             quantity: 1))
        library.upsert(Trade(account: "broker", date: "2026-08-31", id: "b", type: .opening, instrument: "spy-chf",
                             quantity: 1))
        library.upsert(Valuation(account: "broker", date: "2026-08-31", cash: 0))

        let result = await Self.service(client).fetch(for: library, on: Self.checkIn)
        #expect(result.isComplete)
        // 138.42 USD ÷ 1.1398 = 121.442 EUR; × 0.9312 = 113.087 CHF.
        #expect(result.prices.map(\.price) == [d("113.087"), d("121.442")])
        #expect(result.prices.map(\.currency) == [.chf, .eur])
        #expect(result.fx.map(\.quote) == [.chf, .usd])
        // One Yahoo request serves both instruments.
        #expect(await client.requests(matching: "chart/SPY").count == 1)
    }

    @Test func manualUnknownAndUnsupportedInstrumentsAreListed() async throws {
        var library = NeedsLibrary.make()
        library.instruments["aapl"]?.priceSource = PriceSource(provider: .eodhd, symbol: "AAPL.US")
        let client = Self.client()
        let result = await Self.service(client).fetch(for: library, on: Self.checkIn)

        // A provider the app doesn't fetch from counts as typed in.
        for id: InstrumentID in ["aapl", "btc", "private-fund", "typed-in"] {
            let typed = try #require(result.result(for: .instrument(id)))
            #expect(typed.status == .manual && !typed.isFailure, "\(id)")
        }
        #expect(result.failures.map(\.item) == [.instrument("mystery")])
        #expect(result.result(for: .instrument("mystery"))?.failureReason
            == "The instrument \"mystery\" isn't in the library.")
        #expect(result.fx.map(\.quote) == [.chf, .usd])
        #expect(await client.requests(matching: "chart/").isEmpty)
    }

    @Test func onlySymbolsLeaveTheDevice() async throws {
        let library = try Self.exampleLibrary()
        let client = Self.client()
        _ = await Self.service(client).fetch(for: library, on: Self.checkIn)

        var amounts: Set<String> = []
        for valuation in library.allValuations {
            for amount in [valuation.balance, valuation.cash, valuation.flow].compactMap({ $0 }) {
                amounts.insert(amount.fileString)
            }
            for position in valuation.positions {
                amounts.insert(position.quantity.fileString)
                if let cost = position.costBasis { amounts.insert(cost.fileString) }
            }
        }
        for request in await client.requests {
            let components = try #require(URLComponents(url: request.url, resolvingAgainstBaseURL: false))
            let sent = request.url.pathComponents + (components.queryItems ?? []).compactMap(\.value)
            #expect(Set(sent).isDisjoint(with: amounts), "\(request.url)")
            #expect(Set(request.headers.keys).isSubset(of: ["User-Agent"]))
        }
    }

    /// The standard service fetches any HICP from Eurostat: the library's
    /// own and each plan currency's, not a fixed one.
    @Test func theStandardServiceFetchesTheLibrarysIndices() async throws {
        let service = Self.service(MockHTTPClient())
        var library = try Self.exampleLibrary()
        #expect(service.indices(for: library) == [.hicpIT])
        #expect(service.indexProvider(for: "hicp-se")?.index == "hicp-se")
        #expect(service.indexProvider(for: .cpiUS)?.source == .bls)
        #expect(service.indexProvider(for: .cpiGB)?.source == .ons)
        #expect(service.indexProvider(for: "cpi-jp") == nil)
        library.settings.inflationIndex = "cpi-jp"
        #expect(service.indices(for: library).isEmpty)
        #expect(service.needs(for: library, on: Self.checkIn).indices.isEmpty)

        library.settings.inflationIndex = nil
        library.settings.taxResidence = .ch
        let client = Self.client()
        let result = await Self.service(client).fetch(for: library, on: Self.checkIn)
        #expect(result.result(for: .index("hicp-ch"))?.failureReason == nil)
        #expect(result.result(for: .index(.hicpIT)) == nil)
        #expect(Set(result.indices.map(\.index)) == ["hicp-ch"])
        let eurostat = await client.requests.map(\.url.absoluteString).filter { $0.contains("prc_hicp_minr") }
        #expect(eurostat.count == 1 && eurostat[0].contains("geo=CH"))
    }

    /// Living in the US, the library's index is the CPI-U from the BLS; in
    /// the UK, the CPI from the ONS.
    @Test func theStandardServiceFetchesTheUSAndUKIndices() async throws {
        var library = try Self.exampleLibrary()
        library.settings.taxResidence = .us
        let client = Self.client()
        await client.on("CUUR0000SA0", json: BLSResponses.twoYears)
        await client.on("timeseries/d7bt/mm23", json: ONSResponses.series)
        let us = await Self.service(client).fetch(for: library, on: Self.checkIn)
        #expect(us.result(for: .index(.cpiUS))?.failureReason == nil)
        #expect(us.result(for: .index(.cpiUS))?.origin?.source == .bls)
        #expect(us.result(for: .index(.hicpIT)) == nil)
        #expect(Set(us.indices.map(\.index)) == [.cpiUS])
        #expect(Set(us.indices.compactMap(\.source)) == [.bls])
        #expect(us.indices.contains(IndexRecord(index: .cpiUS, date: "2026-08-31", value: d("325.112"), source: .bls)))
        #expect(await client.requests(matching: "prc_hicp_minr").isEmpty)

        library.settings.taxResidence = .gb
        let uk = await Self.service(client).fetch(for: library, on: Self.checkIn)
        #expect(uk.result(for: .index(.cpiGB))?.failureReason == nil)
        #expect(Set(uk.indices.map(\.index)) == [.cpiGB])
        #expect(uk.indices.contains(IndexRecord(index: .cpiGB, date: "2026-08-31", value: d("142.3"), source: .ons)))
    }
}

extension PriceNeeds {
    /// The same needs without the rates asked for themselves.
    var withoutRates: PriceNeeds {
        var needs = self
        needs.rates = []
        return needs
    }
}
