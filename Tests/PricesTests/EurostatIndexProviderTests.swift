import Foundation
import Model
@testable import Prices
import Testing
import TestSupport

struct EurostatIndexProviderTests {
    @Test func monthlyValuesAreDatedTheLastDayOfTheirMonth() async throws {
        let client = MockHTTPClient(["prc_hicp_minr": EurostatResponses.hicpITJulyToSeptember])
        let values = try await EurostatIndexProvider(series: .hicpIT, client: client)
            .values(from: "2026-07", through: "2026-09")
        #expect(values == [
            IndexRecord(index: .hicpIT, date: "2026-07-31", value: d("128.1"), source: .eurostat),
            IndexRecord(index: .hicpIT, date: "2026-08-31", value: d("128.41"), source: .eurostat),
        ])
    }

    @Test func asksForItalysAllItemsIndexWith2015As100() async throws {
        let client = MockHTTPClient(["prc_hicp_minr": EurostatResponses.hicpITJulyToSeptember])
        _ = try await EurostatIndexProvider(series: .hicpIT, client: client)
            .values(from: "2026-07", through: "2026-09")
        let sent = try #require(await client.requests.first)
        #expect(sent.url.absoluteString
            == "https://ec.europa.eu/eurostat/api/dissemination/statistics/1.0/data/prc_hicp_minr"
            + "?format=JSON&lang=EN&coicop18=TOTAL&freq=M&geo=IT&unit=I15"
            + "&sinceTimePeriod=2026-07&untilTimePeriod=2026-09")
    }

    @Test func onlyTheRequestedMonthsAreReturned() async throws {
        let client = MockHTTPClient(["prc_hicp_minr": EurostatResponses.hicpITJulyToSeptember])
        let values = try await EurostatIndexProvider(series: .hicpIT, client: client)
            .values(from: "2026-08", through: "2026-08")
        #expect(values.map(\.date) == ["2026-08-31"])
        #expect(try await EurostatIndexProvider(series: .hicpIT, client: client)
            .values(from: "2026-09", through: "2026-08").isEmpty)
    }

    @Test func readsOlderStylesAndSkipsMissingValues() throws {
        let dataset = try JSONDecoder().decode(EurostatIndexProvider.Dataset.self,
                                               from: Data(EurostatResponses.arrayStyle.utf8))
        let values = try EurostatIndexProvider.monthlyValues(in: dataset, service: "Eurostat")
        #expect(values.map(\.month) == ["2025-10", "2025-12"])
        #expect(values.map(\.value) == [d("126.1"), d("126.3")])
    }

    @Test func aDatasetWithSeveralSeriesIsRejected() async throws {
        let client = MockHTTPClient(["prc_hicp_minr": EurostatResponses.twoCountries])
        await #expect(throws: PriceFetchError.malformedResponse(service: "Eurostat",
                                                                detail: "more than one geo in the series")) {
            _ = try await EurostatIndexProvider(series: .hicpIT, client: client)
                .values(from: "2026-07", through: "2026-07")
        }
    }

    @Test func errorsCarryEurostatsLabel() async throws {
        let client = MockHTTPClient()
        await client.on("prc_hicp_minr", HTTPResponse(statusCode: 400, text: EurostatResponses.badFilter))
        await #expect(throws: PriceFetchError.httpStatus(service: "Eurostat", code: 400,
                                                         message: "Invalid filter value: unit=I99")) {
            _ = try await EurostatIndexProvider(series: .hicpIT, client: client)
                .values(from: "2026-07", through: "2026-09")
        }
    }

    @Test func everyHICPHasASeries() async throws {
        #expect(EurostatIndexProvider.Series.hicp(.hicpIT) == .hicpIT)
        let germany = try #require(EurostatIndexProvider.Series.hicp("hicp-de"))
        #expect(germany.index == "hicp-de" && germany.dataset == "prc_hicp_minr")
        #expect(germany.dimensions == ["freq": "M", "unit": "I15", "coicop18": "TOTAL", "geo": "DE"])
        #expect(EurostatIndexProvider.Series.hicpEA.dimensions["geo"] == "EA")
        #expect(EurostatIndexProvider.Series.hicp("hicp-ch")?.dimensions["geo"] == "CH")
        // Eurostat codes Greece EL.
        #expect(EurostatIndexProvider.Series.hicp("hicp-gr")?.dimensions["geo"] == "EL")
        #expect(EurostatIndexProvider.Series.hicp("hicp-us") == nil)
        #expect(EurostatIndexProvider.Series.hicp("cpi-us") == nil)
        for country in IndexID.hicpCountries {
            #expect(EurostatIndexProvider.Series.hicp(IndexID.hicp(country)!) != nil, "\(country)")
        }

        let client = MockHTTPClient(["prc_hicp_minr": EurostatResponses.hicpITJulyToSeptember])
        let values = try await EurostatIndexProvider(series: germany, client: client)
            .values(from: "2026-07", through: "2026-09")
        #expect(values.map(\.index) == ["hicp-de", "hicp-de"])
        #expect(try #require(await client.requests.first).url.absoluteString
            .contains("coicop18=TOTAL&freq=M&geo=DE&unit=I15"))
    }

    @Test func otherSeriesCanBeConfigured() async throws {
        let series = EurostatIndexProvider.Series(
            index: "hicp-ea", dataset: "prc_hicp_minr",
            dimensions: ["freq": "M", "unit": "I25", "coicop18": "TOTAL", "geo": "EA"])
        let client = MockHTTPClient(["prc_hicp_minr": EurostatResponses.hicpITJulyToSeptember])
        let provider = EurostatIndexProvider(series: series, client: client)
        #expect(provider.index == "hicp-ea")
        let values = try await provider.values(from: "2026-07", through: "2026-07")
        #expect(values.first?.index == "hicp-ea")
        #expect(try #require(await client.requests.first).url.absoluteString.contains("geo=EA&unit=I25"))
    }
}
