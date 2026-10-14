import Foundation
import Model

// The Overview's history chart (UI.md, "Overview", "Your money over time"):
// how far back it reaches, how far ahead a projection runs, and what it
// draws for a range.

/// How far back a history chart reaches (UI.md, "Overview": 1Y, 3Y, 5Y,
/// All), remembered on the device by its raw value.
public enum HistoryRange: String, CaseIterable, Hashable, Sendable {
    case oneYear = "1Y"
    case threeYears = "3Y"
    case fiveYears = "5Y"
    case all = "All"

    /// The years the range spans, or `nil` for all of the history.
    public var years: Int? {
        switch self {
        case .oneYear: 1
        case .threeYears: 3
        case .fiveYears: 5
        case .all: nil
        }
    }

    /// Where the history starts for this range, ending at `end`; `nil` for all of it.
    public func start(before end: Date, calendar: Calendar = .current) -> Date? {
        years.flatMap { calendar.date(byAdding: .year, value: -$0, to: end) }
    }
}

/// How far ahead a projection is shown: to retirement, or 5, 10, 20 or 30
/// years after it. A plan running to 95 makes eight years of history a
/// sliver, so the chart stops earlier than the plan's end. Once retirement
/// is behind, the years count from today instead and *To retirement* isn't
/// offered. Remembered on the device.
public enum FutureHorizon: String, CaseIterable, Hashable, Sendable {
    /// Up to the day you retire.
    case toRetirement
    /// Up to 5 years after you retire.
    case retirementPlus5
    /// Up to 10 years after you retire.
    case retirementPlus10
    /// Up to 20 years after you retire.
    case retirementPlus20
    /// Up to 30 years after you retire.
    case retirementPlus30

    /// Retirement and 10 years after it.
    public static let standard: FutureHorizon = .retirementPlus10

    /// The horizon stored on the device, or ``standard`` when there's none
    /// or it's one that's no longer offered.
    public init(stored: String?) {
        self = stored.flatMap(Self.init(rawValue:)) ?? .standard
    }

    /// The years after retirement (or after today, once retirement is
    /// behind); `nil` for ``toRetirement``.
    public var years: Int? {
        switch self {
        case .toRetirement: nil
        case .retirementPlus5: 5
        case .retirementPlus10: 10
        case .retirementPlus20: 20
        case .retirementPlus30: 30
        }
    }

    /// Whether the horizons count from retirement: while it's ahead of `start`.
    public static func countsFromRetirement(start: Date, retirement: Date?) -> Bool {
        retirement.map { $0 > start } ?? false
    }

    /// The horizons that make sense: all of them while retirement is ahead,
    /// and all but ``toRetirement`` once it's behind.
    public static func choices(start: Date, retirement: Date?) -> [FutureHorizon] {
        countsFromRetirement(start: start, retirement: retirement)
            ? allCases : allCases.filter { $0 != .toRetirement }
    }

    /// This horizon, or ``standard`` when it's ``toRetirement`` and
    /// retirement isn't ahead.
    public func effective(start: Date, retirement: Date?) -> FutureHorizon {
        Self.choices(start: start, retirement: retirement).contains(self) ? self : .standard
    }

    /// Where the projection stops: this many years after retirement while
    /// it's ahead, after `start` once it isn't; never past the plan's end,
    /// and at least a year after `start`.
    public func end(start: Date, retirement: Date?, planEnd: Date, calendar: Calendar = .current) -> Date {
        let horizon = effective(start: start, retirement: retirement)
        func adding(_ years: Int, to date: Date) -> Date {
            calendar.date(byAdding: .year, value: years, to: date) ?? date
        }
        let from = retirement.map { max($0, start) } ?? start
        let end = horizon.years.map { adding($0, to: from) } ?? from
        return min(planEnd, max(end, adding(1, to: start)))
    }
}

/// A chart's time span: history from `start` (all of it when `nil`) and the
/// projection up to `end`.
public struct ProjectionWindow: Hashable, Sendable {
    public var start: Date?
    public var end: Date

    /// The window for `range` back and `horizon` ahead of `now`.
    public init(now: Date, range: HistoryRange, horizon: FutureHorizon, retirement: Date?, planEnd: Date,
         calendar: Calendar = .current) {
        start = range.start(before: now, calendar: calendar)
        end = horizon.end(start: now, retirement: retirement, planEnd: planEnd, calendar: calendar)
    }

    public func history(_ points: [ChartPoint]) -> [ChartPoint] {
        points.filter { point in start.map { point.date >= $0 } ?? true }
    }

    public func fan(_ fan: [FanPoint]) -> [FanPoint] {
        Self.clip(fan, at: end)
    }

    /// The markers between the window's start (or the first date shown) and its end.
    public func markers(_ markers: [ChartMarker], from first: Date? = nil) -> [ChartMarker] {
        let from = start ?? first ?? .distantPast
        return markers.filter { $0.date >= from && $0.date <= end }
    }

    /// The fan up to `horizon`, with a point interpolated at the horizon when
    /// the fan goes beyond it.
    public static func clip(_ fan: [FanPoint], at horizon: Date) -> [FanPoint] {
        var kept = fan.filter { $0.date <= horizon }
        guard let before = kept.last, before.date < horizon,
              let after = fan.first(where: { $0.date > horizon })
        else { return kept }
        let span = after.date.timeIntervalSince(before.date)
        guard span > 0 else { return kept }
        let t = horizon.timeIntervalSince(before.date) / span
        func mix(_ a: Double, _ b: Double) -> Double { a + (b - a) * t }
        kept.append(FanPoint(date: horizon, p10: mix(before.p10, after.p10), p25: mix(before.p25, after.p25),
                             p50: mix(before.p50, after.p50), p75: mix(before.p75, after.p75),
                             p90: mix(before.p90, after.p90)))
        return kept
    }
}

/// The Overview's history chart's data for one range (UI.md, "History chart"): the
/// totals stacked by asset class, debts below zero, and with *Future* on
/// the plan's projection up to the chosen horizon (``FutureHorizon``).
///
/// The past is net worth. With a projection it's plan assets instead (the
/// accounts the plan counts, e.g. without your home), still by asset class:
/// the projection is of plan assets, so the past's total meets its start at
/// today instead of dropping onto it.
public struct HistoryChartData: Hashable, Sendable {
    /// What the past covers: net worth, or plan assets with a projection.
    public var scope: NetWorthScope
    /// The total on each date: the callout's total, the relative axis's 1×,
    /// and the line drawn when nothing can be stacked (every value zero).
    public var points: [ChartPoint]
    /// The totals by asset class, in stacking order (bottom first), on the
    /// same dates as `points` and with their completeness; groups with no
    /// value in the range are left out.
    public var stacked: [ChartSeries]
    public var projection: [FanPoint]
    public var markers: [ChartMarker]
    /// The history's values that use a price more than 31 days older than
    /// their date, for a note under the chart; `nil` when there are none.
    public var oldPrices: OldPriceSummary?
    /// What the history's partial totals (drawn dashed) are missing: prices,
    /// rates, accounts without a value yet; `nil` when it's complete.
    public var missing: MissingValues?

    /// - Parameters:
    ///   - projection: the main plan's portfolio fan, starting at `end`.
    ///     With one, the past covers plan assets (``scope``).
    ///   - markers: retirement, pension starts and the like.
    ///   - horizon: where the projection stops (``FutureHorizon``); all of
    ///     it when `nil`.
    ///
    /// Markers outside what's shown are left out.
    public init(valuator: Valuator, through end: CalendarDate, range: HistoryRange, projection: [FanPoint] = [],
         markers: [ChartMarker] = [], horizon: Date? = nil) {
        let scope: NetWorthScope = projection.isEmpty ? .netWorth : .planAssets
        self.scope = scope
        let start = range.years.map { end.adding(years: -$0) }
        let dates = valuator.dates(.monthEnds, in: scope, through: end)
            .filter { date in start.map { date >= $0 } ?? true }
        // One total per date makes the line, the stacked areas and the missing values.
        let totals = dates.map { valuator.total(on: $0, in: scope) }
        points = totals.map { total in
            ChartPoint(date: total.date.dateValue, value: total.total.doubleValue, isComplete: total.isComplete)
        }
        let byAssetClass = StackedSeries(dimension: .assetClass,
                                         breakdowns: totals.map { valuator.breakdown(of: $0, by: .assetClass) })
        // A group that's zero on every date is left out.
        stacked = byAssetClass.keys.compactMap { key in
            let values = byAssetClass.series(for: key).chartPoints
            guard values.contains(where: { $0.value != 0 }) else { return nil }
            return ChartSeries(id: key.chartID, name: key.description, color: key.chartColor, points: values)
        }
        oldPrices = OldPriceSummary(valuator.oldPrices(in: scope, on: dates))
        missing = points.hasIncompletePoints ? MissingValues(totals.flatMap(\.accounts)) : nil
        self.projection = horizon.map { ProjectionWindow.clip(projection, at: $0) } ?? projection
        let first = points.first?.date ?? end.dateValue
        let last = self.projection.last?.date ?? end.dateValue
        self.markers = markers.filter { $0.date >= first && $0.date <= last }
    }
}
