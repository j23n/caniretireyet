import Foundation
import Model
import Tracker

// What the chart components draw beyond the package's plain values
// (Tracker's `ChartPoint`, `FanPoint`, `ChartMarker` and `ChartColor`, the
// Planner's `SuccessPoint`, `IncomeSegment` and `YearValue`): the line's
// stretches, the value axis, named series and breakdown rows.

/// A stretch of a line drawn one way: complete values solid, incomplete
/// ones (a price or exchange rate missing) dashed, or left out as a gap.
struct ChartSegment: Hashable, Sendable, Identifiable {
    /// Its place along the line, from 0.
    var id: Int
    var isComplete: Bool
    var points: [ChartPoint]
}

extension Array where Element == ChartPoint {
    /// The line in stretches of complete and of incomplete points, in
    /// order. An incomplete stretch also takes the complete point on
    /// either side of it, so a dashed stretch joins the solid line.
    var segments: [ChartSegment] {
        var result: [ChartSegment] = []
        var start = startIndex
        while start < endIndex {
            let isComplete = self[start].isComplete
            var end = start
            while end + 1 < endIndex, self[end + 1].isComplete == isComplete { end += 1 }
            var points = Array(self[start...end])
            if !isComplete {
                if start > startIndex { points.insert(self[start - 1], at: 0) }
                if end + 1 < endIndex { points.append(self[end + 1]) }
            }
            result.append(ChartSegment(id: result.count, isComplete: isComplete, points: points))
            start = end + 1
        }
        return result
    }

    /// The complete points in unbroken runs: a line with gaps where a value
    /// is incomplete, so a value that couldn't be worked out is never drawn
    /// as a lower one (or zero).
    var completeRuns: [ChartSegment] {
        segments.filter(\.isComplete)
    }

    /// Complete points with no complete neighbour: a run of one draws no
    /// line, so charts mark them with a dot.
    var isolatedPoints: [ChartPoint] {
        completeRuns.filter { $0.points.count == 1 }.flatMap(\.points)
    }

    /// Whether some point is incomplete.
    var hasIncompletePoints: Bool {
        contains { !$0.isComplete }
    }
}

/// The value axis of an amount chart (UI.md, "Charts"), worked out from the
/// values it shows, so it reads well whatever they are:
///
/// - The domain always includes zero and spans at least 1 in the chart's
///   currency: flat or near-zero data gets 0…1, not a sliver around zero
///   labelled "0, 0, −0, −0". There's a little room above the highest
///   value, and below the lowest when it's negative.
/// - Ticks fall on round steps (1, 2 or 5 × a power of ten, at least 1),
///   and their compact labels read apart (``label(_:locale:)``).
/// - With a lane, a strip below the lowest value is kept for new-money
///   ticks (``laneTick(up:)``), outside the ticks and gridlines, so they
///   never stretch the scale.
///
/// Charts use it as `.chartYScale(domain: scale.domain)` and
/// `.chartYAxis { amountAxis(hidesAmounts:scale:relativeTo:) }`.
struct AmountScale: Hashable, Sendable {
    /// The y domain, the lane included.
    var domain: ClosedRange<Double>
    /// Where the axis has ticks and gridlines, lowest first.
    var ticks: [Double]
    /// The distance between ticks.
    var step: Double
    /// The strip at the bottom for new-money ticks; `nil` without one.
    var lane: ClosedRange<Double>?
    /// The room above the data for marker labels
    /// (``reservingTop(points:plotHeight:)``); `nil` without it.
    var headroom: ClosedRange<Double>?

    /// About how many steps the axis is divided into.
    static let desiredTicks = 4.0

    init(values: [Double], reservesLane: Bool = false) {
        let finite = values.filter(\.isFinite)
        var low = Swift.min(finite.min() ?? 0, 0)
        var high = Swift.max(finite.max() ?? 0, 0)
        if high - low < 1 {
            if -low > high { low = high - 1 } else { high = low + 1 }
        }
        let span = high - low
        step = Self.niceStep(span / Self.desiredTicks)
        let top = high + span * 0.05
        let bottom = low < 0 ? low - span * 0.05 : low
        var ticks: [Double] = []
        var index = (bottom / step).rounded(.up)
        while index * step <= top + step * 1e-9 {
            let tick = index * step
            ticks.append(tick == 0 ? 0 : tick)
            index += 1
        }
        self.ticks = ticks
        if reservesLane {
            let height = (top - bottom) * 0.1
            lane = (bottom - height)...bottom
            domain = (bottom - height)...top
        } else {
            lane = nil
            domain = bottom...top
        }
    }

    /// A tick's label: compact, with the decimals the ticks need to read apart.
    func label(_ value: Double, locale: Locale = .current) -> String {
        AmountFormat.compact(value, step: step, locale: locale)
    }

    /// Where a new-money tick is drawn in the lane: from its middle up for
    /// money added, down for money taken out, so the direction shows
    /// without colour too. `nil` without a lane.
    func laneTick(up: Bool) -> ClosedRange<Double>? {
        guard let lane else { return nil }
        let height = lane.upperBound - lane.lowerBound
        let middle = lane.lowerBound + height * 0.5
        return up ? middle...(lane.upperBound - height * 0.1) : (lane.lowerBound + height * 0.1)...middle
    }

    /// 1, 2 or 5 × a power of ten, at least `rough`, and at least 1.
    static func niceStep(_ rough: Double) -> Double {
        guard rough.isFinite, rough > 0 else { return 1 }
        let magnitude = pow(10, log10(rough).rounded(.down))
        let residual = rough / magnitude
        let nice: Double = residual <= 1 ? 1 : residual <= 2 ? 2 : residual <= 5 ? 5 : 10
        return Swift.max(nice * magnitude, 1)
    }
}

/// A named series over time, e.g. one asset class in a stacked chart.
struct ChartSeries: Hashable, Sendable, Identifiable {
    var id: String
    var name: String
    var color: ChartColor
    var points: [ChartPoint]
}

extension Array where Element == ChartSeries {
    /// For each date, the top of the stacked areas above zero and the
    /// bottom of those below it (debts): what a stacked chart's value axis
    /// has to reach.
    var stackedExtents: [Double] {
        var up: [Date: Double] = [:]
        var down: [Date: Double] = [:]
        for series in self {
            for point in series.points {
                if point.value >= 0 {
                    up[point.date, default: 0] += point.value
                } else {
                    down[point.date, default: 0] += point.value
                }
            }
        }
        return [Double](up.values) + [Double](down.values)
    }
}

/// One row of a horizontal breakdown: a label, its value and its share.
struct BreakdownRow: Hashable, Sendable, Identifiable {
    var id: String
    var label: String
    /// In the base currency; negative for debts.
    var value: Decimal
    /// The share to show, e.g. of what you own; `nil` hides it.
    var share: Double?
    var color: ChartColor
}

// MARK: - From Tracker

extension BreakdownKey {
    /// The colour of a breakdown group: asset classes and debts have fixed
    /// colours; every other dimension is one hue with labels.
    var chartColor: ChartColor {
        switch self {
        case .assetClass(let assetClass): .assetClass(assetClass)
        case .debts: .debt
        default: .accent
        }
    }

    /// A stable identifier for chart series.
    var chartID: String {
        switch self {
        case .assetClass(let assetClass): "assetClass.\(assetClass.rawValue)"
        case .debts: "debts"
        case .accountGroup(let group): "group.\(group.rawValue)"
        case .currency(let code): "currency.\(code.rawValue)"
        case .institution(let name): "institution.\(name ?? "")"
        case .liquidity(let liquidity): "liquidity.\(liquidity.rawValue)"
        }
    }
}

extension Breakdown {
    /// The slices as rows, largest first, with their share of what you own.
    var rows: [BreakdownRow] {
        slices.map { slice in
            BreakdownRow(id: slice.key.chartID, label: slice.key.description, value: slice.value,
                         share: slice.shareOfAssets?.doubleValue, color: slice.key.chartColor)
        }
    }
}
