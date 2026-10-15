import Foundation
import Model
import Tracker

/// "Actual vs baseline": a baseline's fan from its start date, your actual
/// plan assets over it (the same accounts, in the base currency as the
/// baseline is, and in money of the start date when an inflation index
/// allows), and where you are within it. Progress's years, *Are you on
/// track?* and the Overview's *On track?* all measure with it.
public struct PlanBaselineComparison: Sendable {
    /// Where the latest actual value falls in the baseline's projection.
    public struct Position: Hashable, Sendable {
        public var date: CalendarDate
        public var actual: Decimal
        public var median: Decimal
        /// 0...100, between the 10th and 90th percentiles; `nil` outside them.
        public var percentile: Double?
        public var isBelowTenth: Bool
        public var isAboveNinetieth: Bool

        public init(date: CalendarDate, actual: Decimal, median: Decimal, percentile: Double?, isBelowTenth: Bool,
                    isAboveNinetieth: Bool) {
            self.date = date
            self.actual = actual
            self.median = median
            self.percentile = percentile
            self.isBelowTenth = isBelowTenth
            self.isAboveNinetieth = isAboveNinetieth
        }

        /// `actual − median`: positive is ahead. The "ahead of" and "behind"
        /// lines say it, as ``standing`` says ahead, on or behind plan.
        public var gap: Decimal { actual - median }

        /// Where you are among the baseline's futures: ahead above its 75th
        /// percentile, behind below its 25th, else on plan; within 1% of its
        /// median, on plan (``BaselineStanding``).
        public var standing: Standing {
            Standing(percentile: percentile, isBelowTenth: isBelowTenth, isAboveNinetieth: isAboveNinetieth,
                     isNearMedian: Standing.isNear(actual.doubleValue, median: median.doubleValue))
        }
    }

    /// Whether you're ahead of, on or behind plan (PROGRESS.md, "On track").
    public typealias Standing = BaselineStanding

    public var baseline: Baseline
    public var fan: [FanPoint]
    public var actual: [ChartPoint]
    /// The accounts `actual` counts (``Baseline/comparedAccounts(among:)``):
    /// the baseline's, those that replaced them and those opened since.
    public var accounts: Set<AccountID>
    /// Whether the actual line is in money of the start date (an inflation
    /// index has values for its dates) or of each date.
    public var isInflationAdjusted: Bool
    /// The index the actual line is adjusted with; `nil` when the library has none.
    public var inflation: PlanInflationIndex?
    public var position: Position?

    /// With the library's valuator, so several comparisons share it.
    ///
    /// - Parameters:
    ///   - asOf: the line runs through the latest check-in on or before it.
    ///   - from: where the line starts instead of the baseline's start: a
    ///     year's runs from the year's start, also before a baseline saved
    ///     during it.
    ///   - end: where the line ends instead: a year's at its end.
    public init(baseline: Baseline, library: Library, valuator: Valuator, asOf: CalendarDate,
                from: CalendarDate? = nil, through end: CalendarDate? = nil) {
        self.baseline = baseline
        fan = Self.fan(for: baseline)
        let accounts = baseline.comparedAccounts(among: library.accounts)
        self.accounts = accounts
        let start = baseline.start.date
        // Each check-in, and the month ends between them without one, from
        // the start through the latest check-in (where you stand is as of
        // it), or from and through the days asked for.
        let checkIns = valuator.checkInDates(in: .planAssets, through: asOf)
        let first = from ?? start
        let last = end ?? max(checkIns.last ?? start, start)
        var days = DateGrid.checkInsAndMonthEnds(from: first, through: last, checkIns: checkIns)
        // Also on the start, where the expectation starts: as the library
        // values it now, which differs from the value the baseline started
        // from when past values changed since.
        if first <= start, start <= last, !days.contains(start) {
            days.insert(start, at: days.firstIndex { $0 > start } ?? days.endIndex)
        }
        let values = days.map { date in
            let total = valuator.total(on: date, including: { accounts.contains($0.id) })
            return SeriesPoint(date: date, value: total.total, isComplete: total.isPriced)
        }
        let series = PlanActualSeries(values: values, library: library, valuator: valuator,
                                      currency: library.settings.baseCurrency, inMoneyOf: start)
        actual = series.points
        isInflationAdjusted = series.isInflationAdjusted || series.points.isEmpty
        inflation = series.inflation
        // Where you stand: the latest value after the start (none before it).
        position = series.latest.flatMap { latest in
            latest.date > start ? Self.position(of: latest.value, on: latest.date, in: baseline) : nil
        }
    }

    /// The baseline's fan: its start value, each month end through its
    /// first year-end, where the band widens fastest (with the square root
    /// of time, ``Baseline/percentiles(on:)``), then each year-end after.
    public static func fan(for baseline: Baseline) -> [FanPoint] {
        let knots = baseline.percentileKnots.map(\.date)
        guard let start = knots.first else { return [] }
        let firstYear = DateGrid.checkInsAndMonthEnds(from: start, through: knots.dropFirst().first ?? start,
                                                      checkIns: [])
        return (firstYear + Array(knots.dropFirst(2))).compactMap { day in
            guard let bands = baseline.percentiles(on: day) else { return nil }
            return FanPoint(date: day.dateValue, p10: bands[0], p25: bands[1], p50: bands[2], p75: bands[3],
                            p90: bands[4])
        }
    }

    /// Where `actual` on `date` falls in `baseline`'s futures; `nil` before
    /// it starts.
    public static func position(of actual: Decimal, on date: CalendarDate, in baseline: Baseline) -> Position? {
        guard let bands = baseline.percentiles(on: date) else { return nil }
        let value = actual.doubleValue
        return Position(date: date, actual: actual, median: Decimal(wholeNumber: bands[2]),
                        percentile: Standing.percentile(of: value, in: bands), isBelowTenth: value < bands[0],
                        isAboveNinetieth: value > bands[4])
    }

    /// A plan's baselines with their IDs, newest first.
    public static func baselines(for plan: PlanID, in library: Library) -> [PlanBaselineEntry] {
        (library.projections[plan]?.baselines ?? [:])
            .map { PlanBaselineEntry(id: $0.key, baseline: $0.value) }
            .sorted { ($0.baseline.created, $0.id.rawValue) > ($1.baseline.created, $1.id.rawValue) }
    }
}

/// A saved baseline and its ID (its file name).
public struct PlanBaselineEntry: Hashable, Sendable, Identifiable {
    public var id: BaselineID
    public var baseline: Baseline

    public init(id: BaselineID, baseline: Baseline) {
        self.id = id
        self.baseline = baseline
    }
}
