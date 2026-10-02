import Foundation
import Model

/// Monthly consumer-price-index values from Eurostat's dissemination API,
/// which answers in JSON-stat 2.0.
///
///     GET prc_hicp_minr?format=JSON&lang=EN&coicop18=TOTAL&freq=M&geo=IT&unit=I15
///         &sinceTimePeriod=2026-07&untilTimePeriod=2026-09
///     { "id": ["freq", "unit", "coicop18", "geo", "time"], "size": [1, 1, 1, 1, 2],
///       "dimension": { "time": { "category": { "index": { "2026-07": 0, "2026-08": 1 } } }, … },
///       "value": { "0": 128.1, "1": 128.41 }, … }
///
/// Each value is dated the last day of the month it measures (FILE_FORMAT.md,
/// "Indices"), however late it's published or fetched. ``Series/hicp(_:)``
/// gives the series of any HICP the library may use: a country's
/// (`hicp-de`, `hicp-ch`, …) or the euro area's (`hicp-ea`).
public struct EurostatIndexProvider: PriceIndexProvider {
    /// A monthly Eurostat series: a dataset, and one code for each of its
    /// dimensions other than time.
    public struct Series: Hashable, Sendable {
        public var index: IndexID
        public var dataset: String
        /// Dimension codes, e.g. `["geo": "IT", "unit": "I15"]`.
        public var dimensions: [String: String]

        public init(index: IndexID, dataset: String, dimensions: [String: String]) {
            self.index = index
            self.dataset = dataset
            self.dimensions = dimensions
        }

        /// The all-items HICP an index ID names (`IndexID.hicpArea`), with
        /// 2015 = 100, from `prc_hicp_minr` (ECOICOP 2, which replaced
        /// `prc_hicp_midx` from January 2026); `nil` for an ID that isn't an
        /// HICP. 2015 = 100 keeps each series continuous with values recorded
        /// before Eurostat moved its reference year to 2025.
        public static func hicp(_ index: IndexID) -> Series? {
            guard let area = index.hicpArea else { return nil }
            return Series(index: index, dataset: "prc_hicp_minr",
                          dimensions: ["freq": "M", "unit": "I15", "coicop18": "TOTAL", "geo": geo(area)])
        }

        /// `hicp-it`: Italy's all-items HICP.
        public static let hicpIT = hicp(.hicpIT)!

        /// `hicp-ea`: the euro area's all-items HICP (its changing
        /// composition, `EA`).
        public static let hicpEA = hicp(.hicpEA)!

        /// Eurostat's code for an area: the ISO code, except Greece's (`EL`).
        static func geo(_ area: String) -> String {
            area == "GR" ? "EL" : area
        }
    }

    public static let defaultBaseURL =
        URL(string: "https://ec.europa.eu/eurostat/api/dissemination/statistics/1.0/data/")!

    public let series: Series
    public var index: IndexID { series.index }
    public var source: DataSource { .eurostat }
    public var name: String { "Eurostat" }

    private let fetcher: HTTPFetcher
    private let baseURL: URL

    public init(
        series: Series, client: any HTTPClient = URLSessionHTTPClient(), policy: RequestPolicy = .standard,
        baseURL: URL = EurostatIndexProvider.defaultBaseURL
    ) {
        self.series = series
        self.fetcher = HTTPFetcher(client: client, policy: policy, service: "Eurostat")
        self.baseURL = baseURL
    }

    public func values(from start: YearMonth, through end: YearMonth) async throws -> [IndexRecord] {
        guard start <= end else { return [] }
        let query = [("format", "JSON"), ("lang", "EN")]
            + series.dimensions.sorted { $0.key < $1.key }.map { ($0.key, $0.value) }
            + [("sinceTimePeriod", start.description), ("untilTimePeriod", end.description)]
        let response = try await fetcher.get(baseURL.appending(segments: [series.dataset], query: query))
        try response.requireSuccess(service: name, symbol: series.dataset)
        let dataset = try response.decodeJSON(Dataset.self, service: name)
        return try Self.monthlyValues(in: dataset, service: name)
            .filter { $0.month >= start && $0.month <= end }
            .map { IndexRecord(index: series.index, date: $0.month.lastDay, value: $0.value, source: source) }
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
        let stride = dataset.size[(timePosition + 1)...].reduce(1, *)
        return times.compactMap { label, position -> (month: YearMonth, value: Decimal)? in
            guard let month = parseMonth(label), let value = dataset.value.values[position * stride] else { return nil }
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
