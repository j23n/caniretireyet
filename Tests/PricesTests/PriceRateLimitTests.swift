import Foundation
import Model
@testable import Prices
import Testing
import TestSupport

private func d(_ string: String) -> Decimal { Decimal(fileString: string)! }

/// Free price APIs allow only a few calls a minute: CoinGecko's coins are
/// asked for in one call, and at most a few instruments are fetched at once.
struct PriceRateLimitTests {
    static let today: CalendarDate = "2026-09-30"

    static func coin(_ id: InstrumentID, _ symbol: String, _ currency: CurrencyCode = .eur) -> Instrument {
        Instrument(id: id, name: id.rawValue, kind: .crypto, currency: currency, unit: .share,
                   assetClasses: ["crypto": 1], priceSource: PriceSource(provider: .coingecko, symbol: symbol))
    }

    static func service(_ client: any HTTPClient, maxConcurrentFetches: Int = 4) -> PriceService {
        .standard(client: client, policy: RequestPolicy(timeout: .seconds(60)), today: { today },
                  maxConcurrentFetches: maxConcurrentFetches)
    }

    @Test func coinGeckoCoinsAreFetchedInOneCall() async throws {
        let client = MockHTTPClient()
        await client.on("simple/price", json: """
            {"bitcoin":{"eur":97736.4568,"usd":111400,"last_updated_at":1790758680},\
            "ethereum":{"eur":3812.0625,"usd":4344.5,"last_updated_at":1790758680},\
            "solana":{"eur":181.25,"last_updated_at":1790758680}}
            """)
        let needs = CheckInPriceNeeds(date: Self.today, baseCurrency: .eur, instruments: [
            Self.coin("btc", "bitcoin"), Self.coin("btc-usd", "bitcoin", .usd), Self.coin("eth", "ETH"),
            Self.coin("sol", "solana"), Self.coin("sol-usd", "solana", .usd),
        ])
        let service = Self.service(client)
        let result = await service.fetch(needs)

        let requests = await client.requests.map(\.url.absoluteString)
        #expect(requests == ["https://api.coingecko.com/api/v3/simple/price?ids=bitcoin,ethereum,solana"
            + "&vs_currencies=eur,usd&include_last_updated_at=true&precision=full"])
        #expect(result.prices.map(\.instrument) == ["btc", "btc-usd", "eth", "sol"])
        #expect(result.prices.map(\.price) == [d("97736.4568"), d("111400"), d("3812.0625"), d("181.25")])
        #expect(result.entry(for: .instrument("eth"))?.details?.quote?.resolvedSymbol == "ethereum")
        #expect(result.entry(for: .instrument("btc"))?.details?.quote?.resolvedSymbol == nil)
        #expect(result.entry(for: .instrument("btc"))?.details?.observedAt
            == Date(timeIntervalSince1970: 1_790_758_680))
        // Each coin keeps its own result: Solana has no USD price.
        let failure = try #require(result.entry(for: .instrument("sol-usd"))?.failure)
        #expect(failure == .noData(service: "CoinGecko", detail: "no USD price for solana"))

        // Reopening the check-in uses the cache; only the failed coin is asked again.
        _ = await service.fetch(needs)
        #expect(await client.requests.map(\.url.absoluteString).dropFirst() == [
            "https://api.coingecko.com/api/v3/simple/price?ids=solana&vs_currencies=usd"
                + "&include_last_updated_at=true&precision=full",
        ])
    }

    @Test func anIDTheAnswerLeavesOutStillFallsBackToSearch() async throws {
        let client = MockHTTPClient()
        await client.on("ids=moon&", json: CoinGeckoResponses.spotUnknown)
        await client.on("simple/price", json: """
            {"bitcoin":{"eur":97736.4568,"last_updated_at":1790758680},\
            "moonstone":{"eur":0.385,"last_updated_at":1790758680}}
            """)
        await client.on("search?query=moon", json: CoinGeckoResponses.searchMoon)
        await client.on("search?query=nocoin", json: CoinGeckoResponses.searchNoMatch)
        let needs = CheckInPriceNeeds(date: Self.today, baseCurrency: .eur, instruments: [
            Self.coin("btc", "bitcoin"), Self.coin("moon", "moon"), Self.coin("nope", "nocoin"),
        ])
        let result = await Self.service(client).fetch(needs)

        let spot = await client.requests(matching: "simple/price").map(\.url.absoluteString)
        #expect(spot.first?.contains("ids=bitcoin,moon,nocoin&") == true)
        #expect(result.prices.first { $0.instrument == "btc" }?.price == d("97736.4568"))
        // "moon" isn't an ID CoinGecko knows: the search finds Moonstone.
        let moon = try #require(result.entry(for: .instrument("moon"))?.details?.quote)
        #expect(moon.resolvedSymbol == "moonstone")
        #expect(moon.price == d("0.385"))
        // No coin matches "nocoin".
        guard case .unknownSymbol = try #require(result.entry(for: .instrument("nope"))?.failure) else {
            Issue.record("Expected an unknown symbol")
            return
        }
    }

    @Test func aFailedCallFailsEachCoinOfIt() async throws {
        let client = MockHTTPClient()
        await client.on("simple/price", HTTPResponse(statusCode: 429, text: CoinGeckoResponses.rateLimited))
        let needs = CheckInPriceNeeds(date: Self.today, baseCurrency: .eur, instruments: [
            Self.coin("btc", "bitcoin"), Self.coin("eth", "ETH"),
        ])
        let result = await PriceService.standard(client: client, policy: RequestPolicy(maxRetries: 0),
                                                 today: { Self.today }).fetch(needs)
        #expect(await client.requestCount == 1)
        for id: InstrumentID in ["btc", "eth"] {
            guard case .rateLimited = try #require(result.entry(for: .instrument(id))?.failure) else {
                Issue.record("Expected a rate limit for \(id)")
                continue
            }
        }
    }

    @Test func atMostFourInstrumentsAreFetchedAtOnce() async throws {
        #expect(Self.service(MockHTTPClient()).maxConcurrentFetches == 4)
        let symbols = (1...12).map { index in
            Instrument(id: InstrumentID("etf-\(index)"), name: "ETF \(index)", kind: .etf, currency: .eur, unit: .share,
                       assetClasses: ["equity": 1], priceSource: PriceSource(provider: .yahoo, symbol: "SYM\(index).DE"))
        }
        let many = CountingClient(answer: YahooResponses.vwceSeptember)
        let fetched = await Self.service(many).fetch(CheckInPriceNeeds(date: Self.today, baseCurrency: .eur,
                                                                       instruments: symbols))
        #expect(fetched.prices.count == 12)
        #expect(await many.total == 12)
        #expect(await many.maxInFlight <= 4)
        #expect(await many.maxInFlight > 1)
    }

    /// *Update Prices* fetches one instrument per call, all at once: the
    /// limit is shared by every fetch of the service.
    @Test func theLimitHoldsAcrossFetches() async throws {
        let client = CountingClient(answer: YahooResponses.vwceSeptember)
        let service = Self.service(client, maxConcurrentFetches: 3)
        await withTaskGroup(of: Void.self) { group in
            for index in 1...10 {
                let instrument = Instrument(
                    id: InstrumentID("etf-\(index)"), name: "ETF", kind: .etf, currency: .eur, unit: .share,
                    assetClasses: ["equity": 1], priceSource: PriceSource(provider: .yahoo, symbol: "SYM\(index).DE"))
                group.addTask {
                    _ = await service.fetch(CheckInPriceNeeds(date: Self.today, baseCurrency: .eur,
                                                              instruments: [instrument]))
                }
            }
        }
        #expect(await client.total == 10)
        #expect(await client.maxInFlight <= 3)
    }
}

/// Answers every request with the same body after a short wait, counting
/// how many requests are in flight at once.
actor CountingClient: HTTPClient {
    let answer: String
    private(set) var total = 0
    private(set) var maxInFlight = 0
    private var inFlight = 0

    init(answer: String) {
        self.answer = answer
    }

    func send(_ request: HTTPRequest) async throws -> HTTPResponse {
        total += 1
        inFlight += 1
        maxInFlight = max(maxInFlight, inFlight)
        defer { inFlight -= 1 }
        try await Task.sleep(for: .milliseconds(30))
        return HTTPResponse(statusCode: 200, text: answer)
    }
}
