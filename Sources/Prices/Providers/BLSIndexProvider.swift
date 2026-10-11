import Foundation
import Model

/// Monthly values of the United States' consumer price index (`cpi-us`:
/// CPI-U, all items, not seasonally adjusted, 1982–84 = 100) from the
/// Bureau of Labor Statistics' public API, version 1, which needs no key.
/// The years go in a POST's body: a GET ignores them and answers with the
/// last three years. It answers at most ten years per request, so a longer
/// range takes one request per ten years.
///
///     POST timeseries/data/
///     { "seriesid": ["CUUR0000SA0"], "startyear": "2025", "endyear": "2026" }
///
///     { "status": "REQUEST_SUCCEEDED", "message": [],
///       "Results": { "series": [{ "seriesID": "CUUR0000SA0",
///         "data": [{ "year": "2026", "period": "M08", "periodName": "August", "value": "325.1", … }, …] }] } }
///
/// Each value is dated the last day of the month it measures (docs/schema,
/// history-month.schema.json, `index`). Annual averages (`M13`) and months
/// without a value (`-`) are left out.
public struct BLSIndexProvider: InflationIndexProvider {
    static let baseURL = URL(string: "https://api.bls.gov/publicAPI/v1/timeseries/data/")!
    /// CPI-U, U.S. city average, all items, not seasonally adjusted.
    static let series = "CUUR0000SA0"
    /// The most years version 1 of the API answers in one request.
    static let maxYearsPerRequest = 10

    /// The index this provides: `cpi-us`.
    public var index: IndexID { .cpiUS }
    /// The source written on fetched index records.
    public var source: DataSource { .bls }
    public var name: String { "BLS" }

    private let fetcher: HTTPFetcher

    /// The provider of `cpi-us`; `nil` for any other index.
    public init?(index: IndexID, client: any HTTPClient = URLSessionHTTPClient(), policy: RequestPolicy = .standard) {
        guard index == .cpiUS else { return nil }
        self.fetcher = HTTPFetcher(client: client, policy: policy, service: "BLS")
    }

    /// The published values for the months `start` through `end`, each dated
    /// the last day of its month and sorted. Months not yet published are
    /// left out.
    public func values(from start: YearMonth, through end: YearMonth) async throws -> [IndexRecord] {
        guard start <= end else { return [] }
        var values: [YearMonth: Decimal] = [:]
        for years in Self.yearRanges(from: start.year, through: end.year) {
            let response = try await fetcher.post(Self.baseURL, json: Self.query(years))
            try response.requireSuccess(service: name, symbol: Self.series)
            let body = try response.decodeJSON(Response.self, service: name)
            for value in try Self.monthlyValues(in: body, service: name) {
                values[value.month] = value.value
            }
        }
        return values.filter { $0.key >= start && $0.key <= end }
            .sorted { $0.key < $1.key }
            .map { IndexRecord(index: index, date: $0.key.lastDay, value: $0.value, source: source) }
    }

    /// The years `first` through `last` in runs of at most
    /// ``maxYearsPerRequest``, oldest first: one request each.
    static func yearRanges(from first: Int, through last: Int) -> [ClosedRange<Int>] {
        guard first <= last else { return [] }
        return stride(from: first, through: last, by: maxYearsPerRequest).map {
            $0...min($0 + maxYearsPerRequest - 1, last)
        }
    }

    /// The body asking for the series' values in `years`.
    static func query(_ years: ClosedRange<Int>) throws -> Data {
        let query = Query(seriesid: [series], startyear: String(years.lowerBound), endyear: String(years.upperBound))
        let encoder = JSONEncoder()
        encoder.outputFormatting = .sortedKeys
        return try encoder.encode(query)
    }

    /// The monthly values of the response's series, sorted by month.
    static func monthlyValues(in response: Response, service: String) throws(PriceFetchError)
        -> [(month: YearMonth, value: Decimal)] {
        guard response.status == "REQUEST_SUCCEEDED" else {
            var message = (response.message ?? []).first { !$0.isEmpty } ?? "the request wasn't processed"
            if message.hasSuffix(".") { message.removeLast() }
            throw .noData(service: service, detail: message)
        }
        guard let series = response.results?.series, series.count == 1 else {
            throw .malformedResponse(service: service, detail: "not one series in Results.series")
        }
        if let id = series[0].seriesID, id != Self.series {
            throw .malformedResponse(service: service, detail: "the series is \(id), not \(Self.series)")
        }
        return (series[0].data ?? []).compactMap { point -> (month: YearMonth, value: Decimal)? in
            guard let month = parseMonth(year: point.year, period: point.period),
                  let value = Decimal(fileString: point.value.trimmingCharacters(in: .whitespaces))
            else { return nil }
            return (month, value)
        }.sorted { $0.month < $1.month }
    }

    /// The month of `M01` through `M12` in `year`; `nil` for an annual
    /// average (`M13`) or any other period.
    static func parseMonth(year: String, period: String) -> YearMonth? {
        guard let year = Int(year), period.hasPrefix("M"), let month = Int(period.dropFirst()), (1...12).contains(month)
        else { return nil }
        return YearMonth(year: year, month: month)
    }

    // MARK: - Request and response

    struct Query: Encodable {
        let seriesid: [String]
        let startyear: String
        let endyear: String
    }

    struct Response: Decodable {
        let status: String
        let message: [String]?
        let results: Results?

        enum CodingKeys: String, CodingKey {
            case status, message
            case results = "Results"
        }
    }

    struct Results: Decodable {
        let series: [Series]?
    }

    struct Series: Decodable {
        let seriesID: String?
        let data: [Point]?
    }

    /// One value: `year` "2026", `period` "M08", `value` "325.1". The
    /// value is read as a string, or as a number in case it comes as one.
    struct Point: Decodable {
        let year: String
        let period: String
        let value: String

        enum CodingKeys: String, CodingKey {
            case year, period, value
        }

        init(from decoder: any Decoder) throws {
            let container = try decoder.container(keyedBy: CodingKeys.self)
            year = try Self.text(container, .year)
            period = try container.decode(String.self, forKey: .period)
            value = try Self.text(container, .value)
        }

        private static func text(_ container: KeyedDecodingContainer<CodingKeys>, _ key: CodingKeys) throws -> String {
            if let string = try? container.decode(String.self, forKey: key) { return string }
            return try container.decode(Decimal.self, forKey: key).description
        }
    }
}
