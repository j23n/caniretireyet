import Foundation
#if canImport(FoundationNetworking)
import FoundationNetworking
#endif
@testable import Prices
import Testing

private let url = URL(string: "https://example.test/quote")!
private let rateLimitBody = #"{"status":{"error_code":429,"error_message":"You've exceeded the Rate Limit."}}"#

struct HTTPFetcherTests {
    @Test func timesOutASlowRequest() async throws {
        let client = MockHTTPClient()
        await client.on("quote", HTTPResponse(statusCode: 200, text: "{}"), delay: .seconds(30))
        let fetcher = HTTPFetcher(client: client, policy: RequestPolicy(timeout: .milliseconds(50)), service: "Example")

        let start = ContinuousClock.now
        await #expect(throws: PriceFetchError.timedOut(service: "Example", after: .milliseconds(50))) {
            _ = try await fetcher.get(url)
        }
        #expect(ContinuousClock.now - start < .seconds(5))
    }

    @Test func retriesARateLimitThatAsksForAShortWait() async throws {
        let client = MockHTTPClient()
        await client.on(
            "quote",
            HTTPResponse(statusCode: 429, headers: ["Retry-After": "0"], text: rateLimitBody),
            HTTPResponse(statusCode: 200, text: "{}"))
        let fetcher = HTTPFetcher(client: client, policy: .standard, service: "Example")

        let response = try await fetcher.get(url)
        #expect(response.statusCode == 200)
        #expect(await client.requestCount == 2)
    }

    @Test func givesUpOnALongRetryAfter() async throws {
        let client = MockHTTPClient()
        await client.on("quote", HTTPResponse(statusCode: 429, headers: ["retry-after": "60"], text: "{}"))
        let fetcher = HTTPFetcher(client: client, policy: .standard, service: "CoinGecko")

        await #expect(throws: PriceFetchError.rateLimited(service: "CoinGecko", retryAfter: .seconds(60))) {
            _ = try await fetcher.get(url)
        }
        #expect(await client.requestCount == 1)
        #expect(PriceFetchError.rateLimited(service: "CoinGecko", retryAfter: .seconds(60)).description
            == "CoinGecko is limiting requests. Try again in 60 seconds.")
    }

    @Test func retriesOnceWithoutAHintThenReportsTheRateLimit() async throws {
        let client = MockHTTPClient()
        await client.on("quote", HTTPResponse(statusCode: 429, text: rateLimitBody))
        let policy = RequestPolicy(maxRetries: 1, retryWaitWithoutHint: .milliseconds(1))
        let fetcher = HTTPFetcher(client: client, policy: policy, service: "CoinGecko")

        await #expect(throws: PriceFetchError.rateLimited(service: "CoinGecko", retryAfter: nil)) {
            _ = try await fetcher.get(url)
        }
        #expect(await client.requestCount == 2)
    }

    @Test func mapsTransportErrors() async throws {
        let client = MockHTTPClient()
        await client.on("quote", error: URLError(.notConnectedToInternet))
        let fetcher = HTTPFetcher(client: client, policy: .standard, service: "Example")

        await #expect(throws: PriceFetchError.network(service: "Example", message: "the device is offline")) {
            _ = try await fetcher.get(url)
        }
    }

    @Test func statusCodesBecomeReadableErrors() throws {
        func error(_ status: Int, _ body: String) -> PriceFetchError? {
            do {
                try HTTPResponse(statusCode: status, text: body).requireSuccess(service: "Example", symbol: "XYZ")
                return nil
            } catch {
                return error
            }
        }
        #expect(error(200, "{}") == nil)
        let notFound = #"{"chart":{"result":null,"error":{"code":"Not Found","description":"No such symbol"}}}"#
        #expect(error(404, notFound) == .unknownSymbol(service: "Example", symbol: "XYZ", message: "No such symbol"))
        let refused = #"{"error":{"status":{"error_code":10012,"error_message":"Beyond the allowed time range."}}}"#
        #expect(error(401, refused) == .unauthorized(service: "Example", message: "Beyond the allowed time range."))
        #expect(error(401, refused)?.description
            == "Example refused the request: Beyond the allowed time range. Check the API key in Settings.")
        #expect(error(429, rateLimitBody) == .rateLimited(service: "Example", retryAfter: nil))
        #expect(error(500, "<html><body>Oops</body></html>") == .httpStatus(service: "Example", code: 500, message: nil))
        #expect(error(503, "Service Unavailable\n") == .httpStatus(service: "Example", code: 503,
                                                                  message: "Service Unavailable"))
    }

    @Test func malformedJSONSaysWhatWasWrong() {
        struct Shape: Decodable {
            struct Inner: Decodable { let close: [Decimal] }
            let inner: Inner
        }
        let missing = HTTPResponse(statusCode: 200, text: #"{"other":1}"#)
        #expect(throws: PriceFetchError.malformedResponse(service: "Example", detail: "missing inner")) {
            _ = try missing.decodeJSON(Shape.self, service: "Example")
        }
        let wrongType = HTTPResponse(statusCode: 200, text: #"{"inner":{"close":["x"]}}"#)
        #expect(throws: PriceFetchError.malformedResponse(service: "Example",
                                                          detail: "unexpected value at inner.close[0]")) {
            _ = try wrongType.decodeJSON(Shape.self, service: "Example")
        }
        let html = HTTPResponse(statusCode: 200, text: "<html></html>")
        #expect(throws: PriceFetchError.malformedResponse(service: "Example", detail: "not JSON")) {
            _ = try html.decodeJSON(Shape.self, service: "Example")
        }
    }

    @Test func encodesSymbolsInPathsAndQueries() {
        let base = URL(string: "https://example.test/v8/chart/")!
        #expect(base.appending(segments: ["^GSPC"], query: [("a", "1 2"), ("b", "x+y")]).absoluteString
            == "https://example.test/v8/chart/%5EGSPC?a=1%202&b=x%2By")
        #expect(base.appending(segments: ["EURUSD=X"]).absoluteString == "https://example.test/v8/chart/EURUSD=X")
        #expect(base.appending(segments: ["a/b"]).absoluteString == "https://example.test/v8/chart/a%2Fb")
    }
}
