import Foundation
import Model
@testable import Prices
import Testing
import TestSupport

/// The United Kingdom's CPI from the ONS (`cpi-gb`), from recorded responses.
struct ONSIndexProviderTests {
    private func provider(_ client: MockHTTPClient) throws -> ONSIndexProvider {
        try #require(ONSIndexProvider(index: .cpiGB, client: client))
    }

    @Test func monthlyValuesAreDatedTheLastDayOfTheirMonth() async throws {
        let client = MockHTTPClient(["timeseries/d7bt/mm23": ONSResponses.series])
        let values = try await provider(client).values(from: "2025-11", through: "2026-09")
        // Years and quarters aren't months.
        #expect(values == [
            IndexRecord(index: .cpiGB, date: "2025-11-30", value: d("139.4"), source: .ons),
            IndexRecord(index: .cpiGB, date: "2025-12-31", value: d("139.9"), source: .ons),
            IndexRecord(index: .cpiGB, date: "2026-07-31", value: d("142"), source: .ons),
            IndexRecord(index: .cpiGB, date: "2026-08-31", value: d("142.3"), source: .ons),
        ])
    }

    @Test func asksForTheSeriesCSV() async throws {
        let client = MockHTTPClient(["timeseries/d7bt/mm23": ONSResponses.series])
        _ = try await provider(client).values(from: "2026-07", through: "2026-09")
        let sent = try #require(await client.requests.first)
        #expect(sent.url.absoluteString == "https://www.ons.gov.uk/generator?format=csv"
            + "&uri=/economy/inflationandpriceindices/timeseries/d7bt/mm23")
        #expect(sent.headers.isEmpty)
    }

    @Test func onlyTheRequestedMonthsAreReturned() async throws {
        let client = MockHTTPClient(["timeseries/d7bt/mm23": ONSResponses.series])
        let values = try await provider(client).values(from: "2026-08", through: "2026-08")
        #expect(values.map(\.date) == ["2026-08-31"])
        #expect(try await provider(client).values(from: "2026-09", through: "2026-08").isEmpty)
        #expect(await client.requestCount == 1)
    }

    @Test func anotherSeriesIsRejected() async throws {
        let client = MockHTTPClient(["timeseries/d7bt/mm23": ONSResponses.otherSeries])
        await #expect(throws: PriceFetchError.malformedResponse(service: "ONS", detail: "the series is L522, not D7BT")) {
            _ = try await provider(client).values(from: "2026-07", through: "2026-08")
        }
    }

    @Test func aPageWithoutMonthsIsRejected() async throws {
        let client = MockHTTPClient(["timeseries/d7bt/mm23": ONSResponses.notTheSeries])
        await #expect(throws: PriceFetchError.malformedResponse(service: "ONS", detail: "no monthly values")) {
            _ = try await provider(client).values(from: "2026-07", through: "2026-08")
        }
    }

    @Test func errorsCarryTheONSsLabel() async throws {
        let client = MockHTTPClient()
        await client.on("timeseries/d7bt/mm23", HTTPResponse(statusCode: 404, text: "Not found"))
        await #expect(throws: PriceFetchError.unknownSymbol(service: "ONS", symbol: "D7BT", message: "Not found")) {
            _ = try await provider(client).values(from: "2026-07", through: "2026-08")
        }
    }

    @Test func labelsAreMonthsYearsOrQuarters() {
        #expect(ONSIndexProvider.parseMonth("2026 JAN") == "2026-01")
        #expect(ONSIndexProvider.parseMonth("1989 DEC") == "1989-12")
        #expect(ONSIndexProvider.parseMonth("2026 Q1") == nil)
        #expect(ONSIndexProvider.parseMonth("2026") == nil)
        #expect(ONSIndexProvider.parseMonth("CDID") == nil)
    }

    @Test func readsQuotedFields() {
        #expect(ONSIndexProvider.fields(of: #""2026 JAN","140.2""#) == ["2026 JAN", "140.2"])
        #expect(ONSIndexProvider.fields(of: #"2026 JAN,140.2"#) == ["2026 JAN", "140.2"])
        #expect(ONSIndexProvider.fields(of: #""A, ""quoted"" title","""#) == [#"A, "quoted" title"#, ""])
    }

    @Test func onlyTheUKIndexHasAProvider() {
        let client = MockHTTPClient()
        #expect(ONSIndexProvider(index: .cpiGB, client: client) != nil)
        #expect(ONSIndexProvider(index: .cpiUS, client: client) == nil)
        #expect(ONSIndexProvider(index: "hicp-ea", client: client) == nil)
    }
}
