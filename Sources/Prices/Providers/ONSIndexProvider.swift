import Foundation
import Model

/// Monthly values of the United Kingdom's consumer prices index (`cpi-gb`:
/// CPI, all items, 2015 = 100, series D7BT of the dataset MM23) from the
/// Office for National Statistics' time-series download, which needs no key.
/// It answers the whole series as CSV: a few rows about the series, then
/// its yearly, quarterly and monthly values. Only the monthly rows are read.
///
///     GET generator?format=csv&uri=/economy/inflationandpriceindices/timeseries/d7bt/mm23
///     "Title","CPI INDEX 00: ALL ITEMS 2015=100"
///     "CDID","D7BT"
///     …
///     "2025","138.2"
///     "2025 Q1","136.4"
///     "2025 JAN","135.4"
///
/// Each value is dated the last day of the month it measures (docs/schema,
/// history-month.schema.json, `index`).
public struct ONSIndexProvider: InflationIndexProvider {
    static let seriesURL = URL(string:
        "https://www.ons.gov.uk/generator?format=csv&uri=/economy/inflationandpriceindices/timeseries/d7bt/mm23")!
    /// The series' ID at the ONS (its "CDID").
    static let series = "D7BT"

    /// The index this provides: `cpi-gb`.
    public var index: IndexID { .cpiGB }
    /// The source written on fetched index records.
    public var source: DataSource { .ons }
    public var name: String { "ONS" }

    private let fetcher: HTTPFetcher

    /// The provider of `cpi-gb`; `nil` for any other index.
    public init?(index: IndexID, client: any HTTPClient = URLSessionHTTPClient(), policy: RequestPolicy = .standard) {
        guard index == .cpiGB else { return nil }
        self.fetcher = HTTPFetcher(client: client, policy: policy, service: "ONS")
    }

    /// The published values for the months `start` through `end`, each dated
    /// the last day of its month and sorted. Months not yet published are
    /// left out.
    public func values(from start: YearMonth, through end: YearMonth) async throws -> [IndexRecord] {
        guard start <= end else { return [] }
        let response = try await fetcher.get(Self.seriesURL)
        try response.requireSuccess(service: name, symbol: Self.series)
        guard let text = String(data: response.body, encoding: .utf8) else {
            throw PriceFetchError.malformedResponse(service: name, detail: "not text")
        }
        return try Self.monthlyValues(in: text, service: name)
            .filter { $0.month >= start && $0.month <= end }
            .map { IndexRecord(index: index, date: $0.month.lastDay, value: $0.value, source: source) }
    }

    /// The monthly values of the series' CSV, sorted by month. Throws when
    /// the CSV names another series or has no monthly value at all.
    static func monthlyValues(in csv: String, service: String) throws(PriceFetchError)
        -> [(month: YearMonth, value: Decimal)] {
        var values: [YearMonth: Decimal] = [:]
        for line in csv.split(whereSeparator: \.isNewline) {
            let fields = Self.fields(of: line)
            guard fields.count >= 2 else { continue }
            let label = fields[0].trimmingCharacters(in: CharacterSet(charactersIn: "\u{FEFF}").union(.whitespaces))
            let value = fields[1].trimmingCharacters(in: .whitespaces)
            if label == "CDID", value.uppercased() != Self.series {
                throw .malformedResponse(service: service, detail: "the series is \(value), not \(Self.series)")
            }
            guard let month = parseMonth(label), let number = Decimal(fileString: value) else { continue }
            values[month] = number
        }
        guard !values.isEmpty else { throw .malformedResponse(service: service, detail: "no monthly values") }
        return values.map { (month: $0.key, value: $0.value) }.sorted { $0.month < $1.month }
    }

    /// `2025 JAN`; `nil` for a year (`2025`), a quarter (`2025 Q1`) or any
    /// other label.
    static func parseMonth(_ label: String) -> YearMonth? {
        let parts = label.split(separator: " ")
        guard parts.count == 2, let year = Int(parts[0]),
              let month = monthNames.firstIndex(of: parts[1].uppercased())
        else { return nil }
        return YearMonth(year: year, month: month + 1)
    }

    private static let monthNames = ["JAN", "FEB", "MAR", "APR", "MAY", "JUN",
                                     "JUL", "AUG", "SEP", "OCT", "NOV", "DEC"]

    /// The fields of one CSV row: comma-separated, each optionally in
    /// double quotes, with `""` for a quote inside one.
    static func fields(of line: Substring) -> [String] {
        var fields: [String] = []
        var field = ""
        var quoted = false
        var characters = line.makeIterator()
        while let character = characters.next() {
            if quoted {
                if character == "\"" {
                    // A doubled quote is a quote; a single one ends the field's quoted part.
                    var lookahead = characters
                    if lookahead.next() == "\"" {
                        field.append("\"")
                        characters = lookahead
                    } else {
                        quoted = false
                    }
                } else {
                    field.append(character)
                }
            } else if character == "\"" {
                quoted = true
            } else if character == "," {
                fields.append(field)
                field = ""
            } else {
                field.append(character)
            }
        }
        fields.append(field)
        return fields
    }
}
