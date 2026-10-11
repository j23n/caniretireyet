import Foundation
import Model

// The time span of a chart that continues history into a projection: how
// far back (``OverviewRange``) and how far ahead (``FutureHorizon``), chosen
// together in one control (UI.md, "Overview", "Your money over time").
// Without SwiftUI, so it can be tested on Linux.

/// How far ahead a projection is shown: to retirement, or 5, 10, 20 or 30
/// years after it. A plan running to 95 makes eight years of history a
/// sliver, so the chart stops earlier than the plan's end. Once retirement
/// is behind, the years count from today instead and *To retirement* isn't
/// offered. Remembered on the device (`AppPreferences.futureHorizon`).
enum FutureHorizon: String, CaseIterable, Hashable, Sendable {
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
    static let standard: FutureHorizon = .retirementPlus10

    /// The horizon stored on the device, or ``standard`` when there's none
    /// or it's one that's no longer offered.
    init(stored: String?) {
        self = stored.flatMap(Self.init(rawValue:)) ?? .standard
    }

    /// The years after retirement (or after today, once retirement is
    /// behind); `nil` for ``toRetirement``.
    var years: Int? {
        switch self {
        case .toRetirement: nil
        case .retirementPlus5: 5
        case .retirementPlus10: 10
        case .retirementPlus20: 20
        case .retirementPlus30: 30
        }
    }

    /// Whether the horizons count from retirement: while it's ahead of `start`.
    static func countsFromRetirement(start: Date, retirement: Date?) -> Bool {
        retirement.map { $0 > start } ?? false
    }

    /// In the menu: "Retirement + 10 years", or "+10 years" once retirement
    /// is behind.
    func title(fromRetirement: Bool) -> String {
        guard let years else { return "To retirement" }
        return fromRetirement ? "Retirement + \(years) years" : "+\(years) years"
    }

    /// In the control's label, after the past range: "5Y · retirement +10".
    func shortTitle(fromRetirement: Bool) -> String {
        guard let years else { return "to retirement" }
        return fromRetirement ? "retirement +\(years)" : "+\(years) years"
    }

    /// In the control's label where room is short (an iPhone): "5Y → ret. +10".
    func compactTitle(fromRetirement: Bool) -> String {
        guard let years else { return "retiring" }
        return fromRetirement ? "ret. +\(years)" : "+\(years)y"
    }

    /// The horizons that make sense: all of them while retirement is ahead,
    /// and all but ``toRetirement`` once it's behind.
    static func choices(start: Date, retirement: Date?) -> [FutureHorizon] {
        countsFromRetirement(start: start, retirement: retirement)
            ? allCases : allCases.filter { $0 != .toRetirement }
    }

    /// This horizon, or ``standard`` when it's ``toRetirement`` and
    /// retirement isn't ahead.
    func effective(start: Date, retirement: Date?) -> FutureHorizon {
        Self.choices(start: start, retirement: retirement).contains(self) ? self : .standard
    }

    /// Where the projection stops: this many years after retirement while
    /// it's ahead, after `start` once it isn't; never past the plan's end,
    /// and at least a year after `start`.
    func end(start: Date, retirement: Date?, planEnd: Date, calendar: Calendar = .current) -> Date {
        let horizon = effective(start: start, retirement: retirement)
        func adding(_ years: Int, to date: Date) -> Date {
            calendar.date(byAdding: .year, value: years, to: date) ?? date
        }
        let from = retirement.map { max($0, start) } ?? start
        let end = horizon.years.map { adding($0, to: from) } ?? from
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

/// The control's label for a time span: "5Y", or "5Y · retirement +10"
/// while the future is shown ("5Y → ret. +10" when `compact`; "5Y · +10
/// years" once retirement is behind).
func timeSpanTitle(range: OverviewRange, horizon: FutureHorizon?, fromRetirement: Bool,
                   compact: Bool = false) -> String {
    guard let horizon else { return range.title }
    return compact
        ? "\(range.title) → \(horizon.compactTitle(fromRetirement: fromRetirement))"
        : "\(range.title) · \(horizon.shortTitle(fromRetirement: fromRetirement))"
}
