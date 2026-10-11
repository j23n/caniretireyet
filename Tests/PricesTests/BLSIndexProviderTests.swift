import Foundation
import Model
@testable import Prices
import Testing
import TestSupport

/// The United States' CPI-U from the BLS (`cpi-us`), from recorded responses.
struct BLSIndexProviderTests {
    private func provider(_ client: MockHTTPClient) throws -> BLSIndexProvider {
        try #require(BLSIndexProvider(index: .cpiUS, client: client))
    }

    @Test func monthlyValuesAreDatedTheLastDayOfTheirMonth() async throws {
        let client = MockHTTPClient(["CUUR0000SA0": BLSResponses.twoYears])
        let values = try await provider(client).values(from: "2025-10", through: "2026-09")
        // November has no value and the annual average isn't a month.
        #expect(values == [
            IndexRecord(index: .cpiUS, date: "2025-10-31", value: d("322.4"), source: .bls),
            IndexRecord(index: .cpiUS, date: "2025-12-31", value: d("321.95"), source: .bls),
            IndexRecord(index: .cpiUS, date: "2026-07-31", value: d("324.804"), source: .bls),
            IndexRecord(index: .cpiUS, date: "2026-08-31", value: d("325.112"), source: .bls),
        ])
    }

    /// The years go in a POST's body: a GET ignores them and answers with
    /// the last three years.
    @Test func asksForTheSeriesYearsInTheBody() async throws {
        let client = MockHTTPClient(["CUUR0000SA0": BLSResponses.twoYears])
        _ = try await provider(client).values(from: "2025-12", through: "2026-09")
        let sent = try #require(await client.requests.first)
        #expect(sent.method == "POST")
        #expect(sent.url.absoluteString == "https://api.bls.gov/publicAPI/v1/timeseries/data/")
        #expect(sent.headers == ["Content-Type": "application/json"])
        let body = try #require(sent.body)
        #expect(String(decoding: body, as: UTF8.self)
            == #"{"endyear":"2026","seriesid":["CUUR0000SA0"],"startyear":"2025"}"#)
    }

    @Test func onlyTheRequestedMonthsAreReturned() async throws {
        let client = MockHTTPClient(["CUUR0000SA0": BLSResponses.twoYears])
        let values = try await provider(client).values(from: "2026-08", through: "2026-08")
        #expect(values.map(\.date) == ["2026-08-31"])
        #expect(try await provider(client).values(from: "2026-09", through: "2026-08").isEmpty)
    }

    /// Ten years a request: 2006 through 2025 is two.
    @Test func aLongRangeTakesARequestPerTenYears() async throws {
        let client = MockHTTPClient()
        await client.on(#""startyear":"2006""#, json: BLSResponses.olderPage)
        await client.on(#""startyear":"2016""#, json: BLSResponses.newerPage)
        let values = try await provider(client).values(from: "2006-01", through: "2025-12")
        #expect(values.map(\.date) == ["2015-12-31", "2016-01-31"])
        #expect(await client.requestCount == 2)
        #expect(BLSIndexProvider.yearRanges(from: 2006, through: 2025) == [2006...2015, 2016...2025])
        #expect(BLSIndexProvider.yearRanges(from: 1996, through: 2026) == [1996...2005, 2006...2015, 2016...2025,
                                                                           2026...2026])
        #expect(BLSIndexProvider.yearRanges(from: 2026, through: 2026) == [2026...2026])
    }

    @Test func aRequestNotProcessedSaysWhy() async throws {
        let client = MockHTTPClient(["CUUR0000SA0": BLSResponses.notProcessed])
        await #expect(throws: PriceFetchError.noData(service: "BLS", detail: "Request could not be serviced, as the "
            + "daily threshold for total number of requests allocated to the user has been reached")) {
            _ = try await provider(client).values(from: "2026-07", through: "2026-08")
        }
    }

    @Test func anotherSeriesIsRejected() async throws {
        let client = MockHTTPClient(["CUUR0000SA0": BLSResponses.otherSeries])
        await #expect(throws: PriceFetchError.malformedResponse(service: "BLS",
                                                                detail: "the series is CUSR0000SA0, not CUUR0000SA0")) {
            _ = try await provider(client).values(from: "2026-07", through: "2026-08")
        }
    }

    @Test func errorsCarryTheBLSsLabel() async throws {
        let client = MockHTTPClient()
        await client.on("CUUR0000SA0", HTTPResponse(statusCode: 500, text: "Internal Server Error"))
        await #expect(throws: PriceFetchError.httpStatus(service: "BLS", code: 500, message: "Internal Server Error")) {
            _ = try await provider(client).values(from: "2026-07", through: "2026-08")
        }
    }

    @Test func periodsAreMonths() {
        #expect(BLSIndexProvider.parseMonth(year: "2026", period: "M01") == "2026-01")
        #expect(BLSIndexProvider.parseMonth(year: "2026", period: "M12") == "2026-12")
        #expect(BLSIndexProvider.parseMonth(year: "2026", period: "M13") == nil)
        #expect(BLSIndexProvider.parseMonth(year: "2026", period: "S01") == nil)
    }

    @Test func onlyTheUSIndexHasAProvider() {
        let client = MockHTTPClient()
        #expect(BLSIndexProvider(index: .cpiUS, client: client) != nil)
        #expect(BLSIndexProvider(index: .cpiGB, client: client) == nil)
        #expect(BLSIndexProvider(index: .hicpIT, client: client) == nil)
    }
}
