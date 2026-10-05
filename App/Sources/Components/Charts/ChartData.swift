import Foundation
import Model
import Tracker

// Plain value inputs for the chart components. Charts never read stores:
// screens turn Tracker and Planner results into these (the adapters at the
// bottom cover Tracker's), so a chart can be previewed with made-up numbers.

/// A colour role from the design system, resolved to a `Color` by
/// `Palette.color(for:)` for washes and fills, and `Palette.stroke(for:)`
/// for lines and small marks. Kept free of SwiftUI so chart data can be
/// built anywhere.
enum ChartColor: Hashable, Sendable, Codable {
    /// An asset class's fixed colour (UI.md, "Colour in charts").
    case assetClass(AssetClass)
    /// Debts, in the asset-class breakdown.
    case debt
    /// A categorical slot, 0-based, in the palette's fixed order. Use for
    /// series that aren't asset classes (income sources, two plans).
    case series(Int)
    /// The one hue (blue) for single-series charts: fan charts, success
    /// curves, account groups.
    case accent
    /// Actual history, drawn in ink so it never looks projected.
    case ink
    /// Something neutral, e.g. the "Other" bar of a breakdown.
    case neutral
    /// Taxes paid, on top of retirement income: a neutral that isn't a
    /// source, and stays apart from every series hue in light and dark.
    case taxes
    /// A good change (▲), with a sign and arrow as well.
    case positive
    /// A bad change (▼), with a sign and arrow as well.
    case negative
}

/// One point of a value over time.
struct ChartPoint: Hashable, Sendable, Identifiable {
    var date: Date
    var value: Double
    /// Whether the value is fully known (no missing price or rate).
    var isComplete: Bool = true

    var id: Date { date }
}

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
/// `.chartYAxis { amountAxis(hidesAmounts:scale:) }`.
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

    init(values: [Double], reservesLane: Bool = false, desiredTicks: Int = 4) {
        let finite = values.filter(\.isFinite)
        var low = Swift.min(finite.min() ?? 0, 0)
        var high = Swift.max(finite.max() ?? 0, 0)
        if high - low < 1 {
            if -low > high { low = high - 1 } else { high = low + 1 }
        }
        let span = high - low
        step = Self.niceStep(span / Double(Swift.max(desiredTicks, 1)))
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

/// A band around a median at one date: the future part of the net-worth
/// chart, and each point of a fan chart.
struct FanPoint: Hashable, Sendable, Identifiable, Codable {
    var date: Date
    var p10: Double
    var p25: Double
    var p50: Double
    var p75: Double
    var p90: Double

    var id: Date { date }
}

/// Something that happens at a date, marked on a time axis: retirement, a
/// pension start, a windfall, a new-money tick.
struct ChartMarker: Hashable, Sendable, Identifiable, Codable {
    /// What a marker stands for, when the chart needs to know (the time
    /// span counts from retirement).
    enum Kind: Hashable, Sendable, Codable {
        case retirement
        case pension
        case accessible
        case windfall
        case expense
    }

    var date: Date
    var label: String
    var systemImage: String?
    var kind: Kind? = nil

    var id: String { "\(date.timeIntervalSinceReferenceDate) \(label)" }
}

/// The chance of success when retiring at one age.
struct SuccessPoint: Hashable, Sendable, Identifiable, Codable {
    var age: Int
    /// 0...1.
    var success: Double

    var id: Int { age }
}

/// A success curve, for overlaying two plans.
struct SuccessSeries: Hashable, Sendable, Identifiable {
    var id: String
    var name: String
    var color: ChartColor
    var points: [SuccessPoint]
}

/// One source's amount in one year of a stacked income (or tax) chart.
struct IncomeSegment: Hashable, Sendable, Identifiable, Codable {
    var year: Int
    var source: String
    var amount: Double
    var color: ChartColor
    /// A one-off amount (a windfall, severance pay): when it would dwarf the
    /// rest, it runs off the top of the chart instead of setting its scale.
    var isOneOff = false
    /// The amount before its share of the year's taxes, when `amount` is
    /// after them (retirement income); `nil` when they're the same.
    var gross: Double? = nil

    var id: String { "\(year) \(source)" }
}

/// A value in one year, e.g. the spending target over an income chart.
struct YearValue: Hashable, Sendable, Identifiable, Codable {
    var year: Int
    var value: Double

    var id: Int { year }
}

/// One step of a waterfall: a total, or a change between totals.
struct WaterfallStep: Hashable, Sendable, Identifiable {
    enum Kind: Hashable, Sendable {
        /// A bar from zero: the start or end total.
        case total
        /// A floating bar from the running total.
        case change
    }

    var label: String
    var value: Double
    var kind: Kind

    var id: String { label }

    /// Steps for "since last check-in": start, markets, new money, other, end.
    static func steps(for change: ValueChange, startLabel: String = "Before", endLabel: String = "Now") -> [WaterfallStep] {
        [
            WaterfallStep(label: startLabel, value: change.start.doubleValue, kind: .total),
            WaterfallStep(label: "Markets", value: change.market.doubleValue, kind: .change),
            WaterfallStep(label: "New money", value: change.newMoney.doubleValue, kind: .change),
            WaterfallStep(label: "Other", value: change.other.doubleValue, kind: .change),
            WaterfallStep(label: endLabel, value: change.end.doubleValue, kind: .total),
        ]
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

extension ChartPoint {
    init(_ point: SeriesPoint) {
        self.init(date: point.date.dateValue, value: point.value.doubleValue, isComplete: point.isComplete)
    }
}

extension Array where Element == SeriesPoint {
    /// The points as chart points.
    var chartPoints: [ChartPoint] { map(ChartPoint.init) }
}

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

extension StackedSeries {
    /// One chart series per group, in stacking order (bottom first).
    var chartSeries: [ChartSeries] {
        keys.map { key in
            ChartSeries(id: key.chartID, name: key.description, color: key.chartColor,
                        points: series(for: key).chartPoints)
        }
    }
}
