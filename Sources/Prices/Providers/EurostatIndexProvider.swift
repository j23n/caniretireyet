import Foundation
import Model

/// Monthly consumer-price-index values from Eurostat's dissemination API,
/// which answers in JSON-stat 2.0: the all-items HICP of any area the
/// library may use, a country's (`hicp-de`, `hicp-ch`, …) or the euro
/// area's (`hicp-ea`).
///
///     GET prc_hicp_minr?format=JSON&lang=EN&coicop18=TOTAL&freq=M&geo=IT&unit=I15
///         &sinceTimePeriod=2026-07&untilTimePeriod=2026-09
///     { "id": ["freq", "unit", "coicop18", "geo", "time"], "size": [1, 1, 1, 1, 2],
///       "dimension": { "time": { "category": { "index": { "2026-07": 0, "2026-08": 1 } } }, … },
///       "value": { "0": 128.1, "1": 128.41 }, … }
///
/// Each value is dated the last day of the month it measures (docs/schema,
/// history-month.schema.json, `index`), however late it's published or fetched.
public struct EurostatIndexProvider: InflationIndexProvider {
    static let baseURL = URL(string: "https://ec.europa.eu/eurostat/api/dissemination/statistics/1.0/data/")!
    /// The HICP's dataset, ECOICOP 2, which replaced `prc_hicp_midx` from
    /// January 2026. Its values are asked for with 2015 = 100 (`unit=I15`),
    /// which keeps each series continuous with values recorded before
    /// Eurostat moved its reference year to 2025.
    static let hicpDataset = "prc_hicp_minr"

    /// The index this provides, e.g. `hicp-it`.
    public let index: IndexID
    /// Eurostat's code for the index's area: the ISO code, except Greece's (`EL`).
    let geo: String
    /// The source written on fetched index records.
    public var source: DataSource { .eurostat }
    public var name: String { "Eurostat" }

    private let fetcher: HTTPFetcher

    /// The provider of the all-items HICP `index` names (`IndexID.hicpArea`);
    /// `nil` for an index that isn't an HICP.
    public init?(index: IndexID, client: any HTTPClient = URLSessionHTTPClient(), policy: RequestPolicy = .standard) {
        guard let area = index.hicpArea else { return nil }
        self.index = index
        self.geo = area == "GR" ? "EL" : area
        self.fetcher = HTTPFetcher(client: client, policy: policy, service: "Eurostat")
    }

    /// The published values for the months `start` through `end`, each dated
    /// the last day of its month and sorted. Months not yet published are
    /// left out.
    public func values(from start: YearMonth, through end: YearMonth) async throws -> [IndexRecord] {
        guard start <= end else { return [] }
        let url = Self.baseURL.appending(segments: [Self.hicpDataset], query: [
            ("format", "JSON"), ("lang", "EN"), ("coicop18", "TOTAL"), ("freq", "M"), ("geo", geo), ("unit", "I15"),
            ("sinceTimePeriod", start.description), ("untilTimePeriod", end.description),
        ])
        let response = try await fetcher.get(url)
        try response.requireSuccess(service: name, symbol: Self.hicpDataset)
        let dataset = try response.decodeJSON(Dataset.self, service: name)
        return try Self.monthlyValues(in: dataset, service: name)
            .filter { $0.month >= start && $0.month <= end }
            .map { IndexRecord(index: index, date: $0.month.lastDay, value: $0.value, source: source) }
    }

    /// The monthly values of a single-series JSON-stat dataset, sorted by month.
    static func monthlyValues(in dataset: Dataset, service: String) throws(PriceFetchError) -> [(month: YearMonth, value: Decimal)] {
        guard dataset.id.count == dataset.size.count, let timePosition = dataset.id.firstIndex(of: "time") else {
            throw .malformedResponse(service: service, detail: "no time dimension")
        }
        for (position, name) in dataset.id.enumerated() where position != timePosition && dataset.size[position] != 1 {
            throw .malformedResponse(service: service, detail: "more than one \(name) in the series")
        }
        guard let times = dataset.dimension["time"]?.category.index else {
            throw .malformedResponse(service: service, detail: "missing dimension.time.category.index")
        }
        // Every other dimension has one category, so a month's position is its value's.
        return times.compactMap { label, position -> (month: YearMonth, value: Decimal)? in
            guard let month = parseMonth(label), let value = dataset.value.values[position] else { return nil }
            return (month, value)
        }.sorted { $0.month < $1.month }
    }

    /// `2026-08`, or the older `2026M08`.
    static func parseMonth(_ label: String) -> YearMonth? {
        YearMonth(label) ?? YearMonth(label.replacingOccurrences(of: "M", with: "-"))
    }

    // MARK: - JSON-stat

    struct Dataset: Decodable {
        let id: [String]
        let size: [Int]
        let dimension: [String: Dimension]
        let value: Values
    }

    struct Dimension: Decodable {
        let category: Category
    }

    /// A dimension's categories: `index` maps each code to its position. It
    /// may be an object or an array of codes, or absent for one category.
    struct Category: Decodable {
        let index: [String: Int]

        enum CodingKeys: String, CodingKey {
            case index, label
        }

        init(from decoder: any Decoder) throws {
            let container = try decoder.container(keyedBy: CodingKeys.self)
            if let object = try? container.decode([String: Int].self, forKey: .index) {
                index = object
            } else if let codes = try? container.decode([String].self, forKey: .index) {
                index = Dictionary(codes.enumerated().map { ($1, $0) }, uniquingKeysWith: { first, _ in first })
            } else {
                let labels = try container.decode([String: String].self, forKey: .label)
                guard labels.count == 1, let only = labels.keys.first else {
                    throw DecodingError.keyNotFound(CodingKeys.index, .init(
                        codingPath: container.codingPath, debugDescription: "No category index."))
                }
                index = [only: 0]
            }
        }
    }

    /// Values by flat position: an object keyed by position (sparse), or an
    /// array with nulls for missing values.
    struct Values: Decodable {
        let values: [Int: Decimal]

        init(from decoder: any Decoder) throws {
            let container = try decoder.singleValueContainer()
            if let object = try? container.decode([String: Decimal?].self) {
                var values: [Int: Decimal] = [:]
                for (key, value) in object {
                    if let position = Int(key), let value { values[position] = value }
                }
                self.values = values
            } else {
                let array = try container.decode([Decimal?].self)
                var values: [Int: Decimal] = [:]
                for (position, value) in array.enumerated() {
                    if let value { values[position] = value }
                }
                self.values = values
            }
        }
    }
}
