import Foundation
import Model

// The time span of a chart that continues history into a projection: how
// far back (``OverviewRange``) and how far ahead (``FutureHorizon``), chosen
// together in one control (UI.md, "Overview", "Your money over time").
// Without SwiftUI, so it can be tested on Linux.

/// How far ahead a projection is shown. A plan running to 95 makes eight
/// years of history a sliver, so the chart stops earlier unless you ask for
/// the whole plan. Remembered on the device (`AppPreferences.futureHorizon`).
enum FutureHorizon: String, CaseIterable, Hashable, Sendable {
    /// Up to the day you retire.
    case toRetirement
    /// Up to 15 years after you retire: the years when markets matter most.
    case retirementPlus15
    /// 20 years from now.
    case twentyYears
    /// To the plan's end.
    case wholePlan

    /// Retirement and 15 years after it.
    static let standard: FutureHorizon = .retirementPlus15

    /// In the menu.
    var title: String {
        switch self {
        case .toRetirement: "To retirement"
        case .retirementPlus15: "Retirement + 15 years"
        case .twentyYears: "20 years"
        case .wholePlan: "Whole plan"
        }
    }

    /// In the control's label, after the past range: "5Y · to retirement".
    var shortTitle: String {
        switch self {
        case .toRetirement: "to retirement"
        case .retirementPlus15: "retirement +15"
        case .twentyYears: "+20 years"
        case .wholePlan: "whole plan"
        }
    }

    /// In the control's label where room is short (an iPhone): "5Y → ret. +15".
    var compactTitle: String {
        switch self {
        case .toRetirement: "retiring"
        case .retirementPlus15: "ret. +15"
        case .twentyYears: "+20y"
        case .wholePlan: "end"
        }
    }

    /// Whether the horizon depends on a retirement date.
    var needsRetirement: Bool {
        self == .toRetirement || self == .retirementPlus15
    }

    /// The horizons that make sense: the ones counted from retirement only
    /// while retirement is ahead.
    static func choices(start: Date, retirement: Date?) -> [FutureHorizon] {
        allCases.filter { !$0.needsRetirement || retirement.map { $0 > start } == true }
    }

    /// This horizon, or 20 years when it counts from a retirement that
    /// isn't ahead.
    func effective(start: Date, retirement: Date?) -> FutureHorizon {
        Self.choices(start: start, retirement: retirement).contains(self) ? self : .twentyYears
    }

    /// Where the projection stops: never past the plan's end, and at least a
    /// year after `start`.
    func end(start: Date, retirement: Date?, planEnd: Date, calendar: Calendar = .current) -> Date {
        let horizon = effective(start: start, retirement: retirement)
        func adding(_ years: Int, to date: Date) -> Date {
            calendar.date(byAdding: .year, value: years, to: date) ?? date
        }
        let end: Date = switch horizon {
        case .toRetirement: retirement ?? planEnd
        case .retirementPlus15: adding(15, to: retirement ?? start)
        case .twentyYears: adding(20, to: start)
        case .wholePlan: planEnd
        }
        return min(planEnd, max(end, adding(1, to: start)))
    }
}

extension OverviewRange {
    /// Where the history starts for this range, ending at `end`; `nil` for all of it.
    func start(before end: Date, calendar: Calendar = .current) -> Date? {
        years.flatMap { calendar.date(byAdding: .year, value: -$0, to: end) }
    }
}

/// A chart's time span: history from `start` (all of it when `nil`) and the
/// projection up to `end`.
struct ProjectionWindow: Hashable, Sendable {
    var start: Date?
    var end: Date

    /// The window for `range` back and `horizon` ahead of `now`.
    init(now: Date, range: OverviewRange, horizon: FutureHorizon, retirement: Date?, planEnd: Date,
         calendar: Calendar = .current) {
        start = range.start(before: now, calendar: calendar)
        end = horizon.end(start: now, retirement: retirement, planEnd: planEnd, calendar: calendar)
    }

    func history(_ points: [ChartPoint]) -> [ChartPoint] {
        points.filter { point in start.map { point.date >= $0 } ?? true }
    }

    func fan(_ fan: [FanPoint]) -> [FanPoint] {
        Self.clip(fan, at: end)
    }

    /// The markers between the window's start (or the first date shown) and its end.
    func markers(_ markers: [ChartMarker], from first: Date? = nil) -> [ChartMarker] {
        let from = start ?? first ?? .distantPast
        return markers.filter { $0.date >= from && $0.date <= end }
    }

    /// The fan up to `horizon`, with a point interpolated at the horizon when
    /// the fan goes beyond it.
    static func clip(_ fan: [FanPoint], at horizon: Date) -> [FanPoint] {
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

/// The control's label for a time span: "5Y", or "5Y · retirement +15"
/// while the future is shown ("5Y → ret. +15" when `compact`).
func timeSpanTitle(range: OverviewRange, horizon: FutureHorizon?, compact: Bool = false) -> String {
    guard let horizon else { return range.title }
    return compact ? "\(range.title) → \(horizon.compactTitle)" : "\(range.title) · \(horizon.shortTitle)"
}
