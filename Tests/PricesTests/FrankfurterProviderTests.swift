import Foundation
import Model
@testable import Prices
import Testing
import TestSupport

struct FrankfurterProviderTests {
    private func provider(_ routes: [String: String]) -> (FrankfurterProvider, MockHTTPClient) {
        let client = MockHTTPClient(routes)
        return (FrankfurterProvider(client: client), client)
    }

    /// The rate a check-in on `date` gets: the latest of the two weeks before it.
    private func rate(_ provider: FrankfurterProvider, _ quote: CurrencyCode = .usd,
                      onOrBefore date: CalendarDate) async throws -> FXObservation? {
        try await provider.rates(base: .eur, quote: quote, from: date.adding(days: -14), through: date)
            .rate(onOrBefore: date)
    }

    @Test func asksForTheDaysBeforeTheDate() async throws {
        let (provider, client) = provider(["frankfurter": PriceResponses.frankfurterUSDSeptember])
        let rate = try await rate(provider, onOrBefore: "2026-09-30")
        #expect(rate == FXObservation(rate: d("1.1398"), observedOn: "2026-09-30"))

        let request = try #require(await client.requests.first)
        #expect(request.url.absoluteString
            == "https://api.frankfurter.dev/v1/2026-09-16..2026-09-30?base=EUR&symbols=USD")
        #expect(request.headers.isEmpty)
    }

    @Test func aWeekendGetsFridaysRate() async throws {
        let (provider, _) = provider(["frankfurter": PriceResponses.frankfurterUSDSeptember])
        let sunday = try await rate(provider, onOrBefore: "2026-09-27")
        #expect(sunday == FXObservation(rate: d("1.1371"), observedOn: "2026-09-25"))
        let saturday = try await rate(provider, onOrBefore: "2026-09-26")
        #expect(saturday?.observedOn == "2026-09-25")
    }

    @Test func easterMondayGetsThursdaysRate() async throws {
        let (provider, _) = provider(["frankfurter": FrankfurterResponses.easter2026])
        let rate = try await rate(provider, onOrBefore: "2026-04-06")
        #expect(rate == FXObservation(rate: d("1.1087"), observedOn: "2026-04-02"))
    }

    @Test func theSameCurrencyNeedsNoRequest() async throws {
        let (provider, client) = provider([:])
        let rate = try await rate(provider, .eur, onOrBefore: "2026-09-30")
        #expect(rate?.rate == 1)
        #expect(await client.requestCount == 0)
    }

    @Test func noRatesInTheRangeIsNoRate() async throws {
        let (provider, _) = provider(["frankfurter": FrankfurterResponses.empty])
        #expect(try await rate(provider, onOrBefore: "2026-09-30") == nil)
    }

    @Test func anUnknownCurrencyIsReported() async throws {
        let client = MockHTTPClient()
        await client.on("frankfurter", HTTPResponse(statusCode: 404, text: FrankfurterResponses.notFound))
        let provider = FrankfurterProvider(client: client)
        do {
            _ = try await rate(provider, "XYZ", onOrBefore: "2026-09-30")
            Issue.record("Expected an error")
        } catch let error as PriceFetchError {
            #expect(error == .unknownSymbol(service: "Frankfurter (ECB)", symbol: "EUR/XYZ", message: "not found"))
        }
    }

    @Test func ratesForAnotherBaseAreRejected() async throws {
        let usdBase = PriceResponses.frankfurterUSDSeptember
            .replacingOccurrences(of: #""base":"EUR""#, with: #""base":"USD""#)
        let (provider, _) = provider(["frankfurter": usdBase])
        await #expect(throws: PriceFetchError.malformedResponse(service: "Frankfurter (ECB)",
                                                                detail: "rates are for USD, not EUR")) {
            _ = try await rate(provider, onOrBefore: "2026-09-30")
        }
    }
}
