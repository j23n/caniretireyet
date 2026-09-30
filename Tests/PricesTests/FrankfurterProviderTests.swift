import Foundation
import Model
@testable import Prices
import Testing

private func d(_ string: String) -> Decimal { Decimal(fileString: string)! }

struct FrankfurterProviderTests {
    private func provider(_ routes: [String: String]) -> (FrankfurterProvider, MockHTTPClient) {
        let client = MockHTTPClient(routes)
        return (FrankfurterProvider(client: client), client)
    }

    @Test func asksForTheDaysBeforeTheDate() async throws {
        let (provider, client) = provider(["frankfurter": FrankfurterResponses.september])
        let rate = try await provider.rate(base: .eur, quote: .usd, onOrBefore: "2026-09-30")
        #expect(rate == FXObservation(rate: d("1.1398"), observedOn: "2026-09-30"))

        let request = try #require(await client.requests.first)
        #expect(request.url.absoluteString
            == "https://api.frankfurter.dev/v1/2026-09-16..2026-09-30?base=EUR&symbols=USD")
        #expect(request.headers.isEmpty)
    }

    @Test func aWeekendGetsFridaysRate() async throws {
        let (provider, _) = provider(["frankfurter": FrankfurterResponses.september])
        let sunday = try await provider.rate(base: .eur, quote: .usd, onOrBefore: "2026-09-27")
        #expect(sunday == FXObservation(rate: d("1.1371"), observedOn: "2026-09-25"))
        let saturday = try await provider.rate(base: .eur, quote: .usd, onOrBefore: "2026-09-26")
        #expect(saturday.observedOn == "2026-09-25")
    }

    @Test func easterMondayGetsThursdaysRate() async throws {
        let (provider, _) = provider(["frankfurter": FrankfurterResponses.easter2026])
        let rate = try await provider.rate(base: .eur, quote: .usd, onOrBefore: "2026-04-06")
        #expect(rate == FXObservation(rate: d("1.1087"), observedOn: "2026-04-02"))
    }

    @Test func theSameCurrencyNeedsNoRequest() async throws {
        let (provider, client) = provider([:])
        let rate = try await provider.rate(base: .eur, quote: .eur, onOrBefore: "2026-09-30")
        #expect(rate.rate == 1)
        #expect(await client.requestCount == 0)
    }

    @Test func noRatesInTheRangeIsNoData() async throws {
        let (provider, _) = provider(["frankfurter": FrankfurterResponses.empty])
        await #expect(throws: PriceFetchError.noData(service: "Frankfurter (ECB)",
                                                     detail: "no EUR/USD rate on or before 2026-09-30")) {
            _ = try await provider.rate(base: .eur, quote: .usd, onOrBefore: "2026-09-30")
        }
    }

    @Test func anUnknownCurrencyIsReported() async throws {
        let client = MockHTTPClient()
        await client.on("frankfurter", HTTPResponse(statusCode: 404, text: FrankfurterResponses.notFound))
        let provider = FrankfurterProvider(client: client)
        do {
            _ = try await provider.rate(base: .eur, quote: "XYZ", onOrBefore: "2026-09-30")
            Issue.record("Expected an error")
        } catch let error as PriceFetchError {
            #expect(error == .unknownSymbol(service: "Frankfurter (ECB)", symbol: "EUR/XYZ", message: "not found"))
            #expect(error.description == "Frankfurter (ECB) doesn't know \"EUR/XYZ\": not found.")
        }
    }

    @Test func ratesForAnotherBaseAreRejected() async throws {
        let usdBase = FrankfurterResponses.september.replacingOccurrences(of: #""base":"EUR""#, with: #""base":"USD""#)
        let (provider, _) = provider(["frankfurter": usdBase])
        await #expect(throws: PriceFetchError.malformedResponse(service: "Frankfurter (ECB)",
                                                                detail: "rates are for USD, not EUR")) {
            _ = try await provider.rate(base: .eur, quote: .usd, onOrBefore: "2026-09-30")
        }
    }
}
