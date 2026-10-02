import Foundation
import Model

/// A consumer price index, such as the library's own
/// (`Library.effectiveInflationIndex`: by default the HICP of the tax
/// residence), for expressing amounts in the money of another date, such as
/// today's money.
///
/// The index on a date is the latest value dated on or before it. Monthly
/// values are dated at month end, so a mid-month date uses the previous
/// month's value, and dates after the last published value use that value.
/// Dates before the first value have none.
public struct InflationIndex: Sendable {
    public let index: IndexID
    /// The index's values, sorted by date.
    public let records: [IndexRecord]

    /// Indexes the values of `index` among `records`. For duplicate dates the last one wins.
    public init(_ records: some Sequence<IndexRecord>, index: IndexID) {
        var byKey: [IndexKey: IndexRecord] = [:]
        for record in records where record.index == index { byKey[record.key] = record }
        self.index = index
        self.records = byKey.values.sortedByKey()
    }

    /// The values of `index` in the library.
    public init(library: Library, index: IndexID) {
        self.init(library.months.values.lazy.flatMap(\.indices), index: index)
    }

    /// The values of the library's own index (`Library.effectiveInflationIndex`);
    /// `nil` when it has none.
    public init?(library: Library) {
        guard let index = library.effectiveInflationIndex else { return nil }
        self.init(library: library, index: index)
    }

    /// The latest value dated on or before `date`.
    public func value(on date: CalendarDate) -> IndexRecord? {
        records.lastIndex(onOrBefore: date, date: \.date).map { records[$0] }
    }

    /// How much prices grew from `from` to `to`: the index on `to` divided by
    /// the index on `from` (1.02 for 2% inflation). `nil` without both values.
    public func factor(from: CalendarDate, to: CalendarDate) -> Decimal? {
        guard let start = value(on: from)?.value, let end = value(on: to)?.value, start != 0 else { return nil }
        return end / start
    }

    /// The inflation from `from` to `to` as a fraction (0.02 for 2%).
    public func inflation(from: CalendarDate, to: CalendarDate) -> Decimal? {
        factor(from: from, to: to).map { $0 - 1 }
    }

    /// `amount` in money of `from`, expressed in money of `to`: e.g. an
    /// amount from 2020 in today's money is
    /// `convert(amount, from: "2020-12-31", to: today)`.
    public func convert(_ amount: Decimal, from: CalendarDate, to: CalendarDate) -> Decimal? {
        guard let start = value(on: from)?.value, let end = value(on: to)?.value, start != 0 else { return nil }
        return start == end ? amount : amount * end / start
    }

    /// A series in money of `reference` (for example today): each point is
    /// converted from the money of its own date. Points before the first
    /// index value are left out.
    public func series(_ series: [SeriesPoint], inMoneyOf reference: CalendarDate) -> [SeriesPoint] {
        series.compactMap { point in
            convert(point.value, from: point.date, to: reference).map {
                SeriesPoint(date: point.date, value: $0, isComplete: point.isComplete)
            }
        }
    }
}
