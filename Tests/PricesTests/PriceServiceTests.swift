import Foundation
import Model
@testable import Prices
import Testing
import TestSupport

private func d(_ string: String) -> Decimal { Decimal(fileString: string)! }

/// The price service over the made-up example library, with every provider
/// answering from recorded responses.
struct PriceServiceTests {
    static let checkIn: CalendarDate = "2026-09-30"

    /// A client that answers every request a check-in on 2026-09-30 makes.
    static func client() -> MockHTTPClient {
        MockHTTPClient([
            "symbols=USD": FrankfurterResponses.september,
            "symbols=CHF": FrankfurterResponses.septemberCHF,
            "simple/price": CoinGeckoResponses.spotUSD,
            "price/XAU": GoldAPIResponses.gold,
            "chart/VWCE.DE": YahooResponses.vwceSeptember,
            "prc_hicp_minr": EurostatResponses.hicpITJulyToSeptember,
        ])
    }

    static func service(_ client: MockHTTPClient, policy: RequestPolicy = .standard) -> PriceService {
        .standard(client: client, policy: policy, today: { checkIn })
    }

    @Test func fetchesWhatTheExampleLibraryNeeds() async throws {
        let library = try Fixtures.exampleLibrary()
        let client = Self.client()
        let result = await Self.service(client).fetch(for: library, on: Self.checkIn)

        #expect(result.isComplete)
        // The same records the example library holds for its September check-in.
        let september = try #require(library.months["2026-09"])
        #expect(result.prices == september.prices)
        #expect(result.fx == september.fx)
        #expect(result.indices.isEmpty)
        #expect(result.entries.map(\.item) == [
            .instrument("btc"), .instrument("gold"), .instrument("vwce"), .fx(base: .eur, quote: .usd), .index(.hicpIT),
        ])

        // Gold: 3,488.45 USD per troy ounce at 1 EUR = 1.1398 USD is 98.4 EUR per gram.
        let gold = try #require(result.entry(for: .instrument("gold")))
        #expect(gold.source == .goldAPI)
        #expect(gold.symbol == "XAU")
        #expect(gold.details?.quote == Quote(price: d("3488.45"), currency: .usd, unit: .troyOunce,
                                             observedOn: Self.checkIn,
                                             observedAt: Date(timeIntervalSince1970: 1_790_758_787)))
        // Italy's HICP for September isn't out yet; August is the latest.
        #expect(result.entry(for: .index(.hicpIT))?.details?.observedOn == "2026-08-31")

        // One request per item: the EUR/USD rate is shared by the FX entry
        // and the gold conversion.
        #expect(await client.requestCount == 5)
        #expect(await client.requests(matching: "frankfurter").count == 1)
    }

    @Test func reopeningACheckInUsesTheCache() async throws {
        let library = try Fixtures.exampleLibrary()
        let client = Self.client()
        let service = Self.service(client)

        let first = await service.fetch(for: library, on: Self.checkIn)
        #expect(await client.requestCount == 5)
        let second = await service.fetch(for: library, on: Self.checkIn)
        #expect(await client.requestCount == 5)
        #expect(second == first)
        #expect(await service.cache.contains(.init(provider: "yahoo", symbol: "VWCE.DE", date: Self.checkIn)))

        _ = await service.fetch(for: library, on: Self.checkIn, refresh: true)
        #expect(await client.requestCount == 10)
    }

    @Test func missingIndexMonthsAreFilledIn() async throws {
        var library = try Fixtures.exampleLibrary()
        library.months["2026-07"]?.indices = []
        library.months["2026-08"]?.indices = []
        let result = await Self.service(Self.client()).fetch(for: library, on: Self.checkIn)
        #expect(result.indices == [
            IndexRecord(index: .hicpIT, date: "2026-07-31", value: d("128.1"), source: .eurostat),
            IndexRecord(index: .hicpIT, date: "2026-08-31", value: d("128.41"), source: .eurostat),
        ])

        result.apply(to: &library)
        #expect(library.months["2026-08"]?.indices.first?.value == d("128.41"))
        #expect(library.months["2026-09"]?.prices.count == 3)
    }

    @Test func aWeekendCheckInRecordsFridaysValuesOnItsOwnDate() async throws {
        let library = try Fixtures.exampleLibrary()
        let sunday: CalendarDate = "2026-09-27"
        let result = await PriceService.standard(client: Self.client(), today: { Self.checkIn })
            .fetch(for: library, on: sunday)
        #expect(result.prices.first { $0.instrument == "vwce" }
            == PriceRecord(instrument: "vwce", date: sunday, price: d("136.88"), currency: .eur, source: .yahoo))
        #expect(result.fx == [FXRecord(base: .eur, quote: .usd, date: sunday, rate: d("1.1371"), source: .ecb)])
        #expect(result.entry(for: .instrument("vwce"))?.details?.observedOn == "2026-09-25")
        #expect(result.entry(for: .fx(base: .eur, quote: .usd))?.details?.observedOn == "2026-09-25")
    }

    @Test func oneFailureDoesntStopTheRest() async throws {
        let client = MockHTTPClient()
        await client.on("chart/VWCE.DE", HTTPResponse(statusCode: 500, text: "Internal Server Error"))
        await client.on("simple/price", HTTPResponse(statusCode: 429, headers: ["Retry-After": "120"],
                                                     text: CoinGeckoResponses.rateLimited))
        await client.on("symbols=USD", json: FrankfurterResponses.september)
        await client.on("price/XAU", json: GoldAPIResponses.gold)
        await client.on("prc_hicp_minr", json: EurostatResponses.hicpITJulyToSeptember)

        let result = await Self.service(client).fetch(for: try Fixtures.exampleLibrary(), on: Self.checkIn)
        #expect(!result.isComplete)
        #expect(result.prices.map(\.instrument) == ["gold"])
        #expect(result.fx.count == 1)
        #expect(result.failures.map(\.item) == [.instrument("btc"), .instrument("vwce")])
        #expect(result.entry(for: .instrument("vwce"))?.failureReason
            == "Yahoo Finance answered with HTTP 500: Internal Server Error.")
        #expect(result.entry(for: .instrument("btc"))?.failureReason
            == "CoinGecko is limiting requests. Try again in 120 seconds.")
    }

    @Test func aSlowProviderTimesOutAlone() async throws {
        let client = Self.client()
        await client.on("chart/SLOW", HTTPResponse(statusCode: 200, text: YahooResponses.vwceSeptember),
                        delay: .seconds(30))
        var library = try Fixtures.exampleLibrary()
        library.instruments["vwce"]?.priceSource = PriceSource(provider: .yahoo, symbol: "SLOW")

        let start = ContinuousClock.now
        let result = await Self.service(client, policy: RequestPolicy(timeout: .milliseconds(200)))
            .fetch(for: library, on: Self.checkIn)
        #expect(ContinuousClock.now - start < .seconds(10))
        #expect(result.failures.map(\.item) == [.instrument("vwce")])
        #expect(result.entry(for: .instrument("vwce"))?.failureReason
            == "Yahoo Finance didn't answer within 200 ms.")
        #expect(result.prices.count == 2)
    }

    @Test func withoutAnFXRateTheGoldPriceCantBeConverted() async throws {
        let client = MockHTTPClient()
        await client.on("frankfurter", HTTPResponse(statusCode: 503, text: "Service Unavailable"))
        await client.on("simple/price", json: CoinGeckoResponses.spotUSD)
        await client.on("price/XAU", json: GoldAPIResponses.gold)
        await client.on("chart/VWCE.DE", json: YahooResponses.vwceSeptember)
        await client.on("prc_hicp_minr", json: EurostatResponses.hicpITJulyToSeptember)

        let result = await Self.service(client).fetch(for: try Fixtures.exampleLibrary(), on: Self.checkIn)
        #expect(result.fx.isEmpty)
        // btc is priced in USD, as CoinGecko quotes it: no conversion needed.
        #expect(result.prices.map(\.instrument) == ["btc", "vwce"])
        #expect(result.failures.map(\.item) == [.instrument("gold"), .fx(base: .eur, quote: .usd)])
        #expect(result.entry(for: .instrument("gold"))?.failureReason
            == "No USD→EUR rate to convert the price: Frankfurter (ECB) answered with HTTP 503: Service Unavailable.")
    }

    @Test func quotesInAnotherCurrencyConvertThroughTheBase() async throws {
        let client = Self.client()
        let usdChart = YahooResponses.vwceSeptember
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
        library.upsert(Valuation(account: "broker", date: "2026-08-31", positions: [
            Position(instrument: "spy-eur", quantity: 1), Position(instrument: "spy-chf", quantity: 1),
        ]))

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

        #expect(result.entry(for: .instrument("private-fund"))?.outcome == .manual)
        #expect(result.entry(for: .instrument("typed-in"))?.outcome == .manual)
        #expect(result.entry(for: .instrument("mystery"))?.failure == .unknownInstrument("mystery"))
        #expect(result.entry(for: .instrument("aapl"))?.failureReason
            == "There's no \"eodhd\" price provider yet. Enter the price by hand.")
        #expect(result.fx.map(\.quote) == [.chf, .usd])
        #expect(await client.requests(matching: "chart/").isEmpty)
    }

    @Test func onlySymbolsLeaveTheDevice() async throws {
        let library = try Fixtures.exampleLibrary()
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
}
