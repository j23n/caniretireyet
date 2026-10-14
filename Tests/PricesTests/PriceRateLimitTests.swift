import Foundation
import Model
@testable import Prices
import Testing
import TestSupport

/// Free price APIs allow only a few calls a minute: at most a few
/// instruments are fetched at once.
struct PriceRateLimitTests {
    static let today: CalendarDate = "2026-09-30"

    /// The needs of a check-in holding `instruments`.
    static func needs(_ instruments: [Instrument]) -> PriceNeeds {
        PriceNeeds(date: today, baseCurrency: .eur, instruments: instruments.map {
            PriceNeeds.InstrumentDates(instrument: $0.id, details: $0, dates: [today])
        })
    }

    static func service(_ client: any HTTPClient, maxConcurrentFetches: Int = 4) -> PriceService {
        .standard(client: client, policy: RequestPolicy(timeout: .seconds(60)), today: { today },
                  maxConcurrentFetches: maxConcurrentFetches)
    }

    @Test func atMostFourInstrumentsAreFetchedAtOnce() async throws {
        #expect(Self.service(MockHTTPClient()).maxConcurrentFetches == 4)
        let symbols = (1...12).map { index in
            Instrument(id: InstrumentID("etf-\(index)"), name: "ETF \(index)", kind: .etf, currency: .eur, unit: .share,
                       assetClasses: ["equity": 1], priceSource: PriceSource(provider: .yahoo, symbol: "SYM\(index).DE"))
        }
        let many = CountingClient(answer: PriceResponses.yahooVWCESeptember)
        let fetched = await Self.service(many).fetch(Self.needs(symbols))
        #expect(fetched.prices.count == 12)
        #expect(await many.total == 12)
        #expect(await many.maxInFlight <= 4)
        #expect(await many.maxInFlight > 1)
    }

    /// *Update Prices* fetches one instrument per call, all at once: the
    /// limit is shared by every fetch of the service.
    @Test func theLimitHoldsAcrossFetches() async throws {
        let client = CountingClient(answer: PriceResponses.yahooVWCESeptember)
        let service = Self.service(client, maxConcurrentFetches: 3)
        await withTaskGroup(of: Void.self) { group in
            for index in 1...10 {
                let instrument = Instrument(
                    id: InstrumentID("etf-\(index)"), name: "ETF", kind: .etf, currency: .eur, unit: .share,
                    assetClasses: ["equity": 1], priceSource: PriceSource(provider: .yahoo, symbol: "SYM\(index).DE"))
                group.addTask {
                    _ = await service.fetch(Self.needs([instrument]))
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
