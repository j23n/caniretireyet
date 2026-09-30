import Foundation
import Model
import Tracker

// Plain value inputs for the chart components. Charts never read stores:
// screens turn Tracker and Planner results into these (the adapters at the
// bottom cover Tracker's), so a chart can be previewed with made-up numbers.

/// A colour role from the design system, resolved to a `Color` by
/// `Palette.color(for:)`. Kept free of SwiftUI so chart data can be built
/// anywhere.
enum ChartColor: Hashable, Sendable {
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
    /// Something neutral, e.g. waterfall totals.
    case neutral
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

/// A named series over time, e.g. one asset class in a stacked chart.
struct ChartSeries: Hashable, Sendable, Identifiable {
    var id: String
    var name: String
    var color: ChartColor
    var points: [ChartPoint]
}

/// A band around a median at one date: the future part of the net-worth
/// chart, and each point of a fan chart.
struct FanPoint: Hashable, Sendable, Identifiable {
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
struct ChartMarker: Hashable, Sendable, Identifiable {
    var date: Date
    var label: String
    var systemImage: String?

    var id: String { "\(date.timeIntervalSinceReferenceDate) \(label)" }
}

/// The chance of success when retiring at one age.
struct SuccessPoint: Hashable, Sendable, Identifiable {
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
struct IncomeSegment: Hashable, Sendable, Identifiable {
    var year: Int
    var source: String
    var amount: Double
    var color: ChartColor

    var id: String { "\(year) \(source)" }
}

/// A value in one year, e.g. the spending target over an income chart.
struct YearValue: Hashable, Sendable, Identifiable {
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
