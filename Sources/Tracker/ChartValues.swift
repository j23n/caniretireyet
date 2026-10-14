import Foundation
import Model

// Plain values the charts draw. Charts never read stores: the math turns
// Tracker and Planner results into these, so a chart can be previewed with
// made-up numbers and the math is tested on Linux. The Planner adds the
// plan's own (`SuccessPoint`, `IncomeSegment`, `YearValue`).

/// A colour role from the design system, resolved to a colour by the app's
/// `Palette.color(for:)` for washes and fills, and `Palette.stroke(for:)`
/// for lines and small marks. Free of SwiftUI so chart data can be built
/// anywhere.
public enum ChartColor: Hashable, Sendable, Codable {
    /// An asset class's fixed colour (UI.md, "Colour in charts").
    case assetClass(AssetClass)
    /// Debts, in the asset-class breakdown.
    case debt
    /// A categorical slot, 0-based, in the palette's fixed order. Use for
    /// series that aren't asset classes (income sources, the two taxes).
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
}

/// One point of a value over time.
public struct ChartPoint: Hashable, Sendable, Identifiable {
    public var date: Date
    public var value: Double
    /// Whether the value is fully known (no missing price or rate).
    public var isComplete: Bool

    public init(date: Date, value: Double, isComplete: Bool = true) {
        self.date = date
        self.value = value
        self.isComplete = isComplete
    }

    public var id: Date { date }

    /// A point of a Tracker series.
    public init(_ point: SeriesPoint) {
        self.init(date: point.date.dateValue, value: point.value.doubleValue, isComplete: point.isComplete)
    }
}

extension Array where Element == SeriesPoint {
    /// The points as chart points.
    public var chartPoints: [ChartPoint] { map(ChartPoint.init) }
}

/// A band around a median at one date: the future part of the net-worth
/// chart, and each point of a fan chart.
public struct FanPoint: Hashable, Sendable, Identifiable, Codable {
    public var date: Date
    public var p10: Double
    public var p25: Double
    public var p50: Double
    public var p75: Double
    public var p90: Double

    public init(date: Date, p10: Double, p25: Double, p50: Double, p75: Double, p90: Double) {
        self.date = date
        self.p10 = p10
        self.p25 = p25
        self.p50 = p50
        self.p75 = p75
        self.p90 = p90
    }

    public var id: Date { date }
}

/// Something that happens at a date, marked on a time axis: retirement, a
/// pension start, a windfall, a new-money tick.
public struct ChartMarker: Hashable, Sendable, Identifiable, Codable {
    /// What a marker stands for, when the chart needs to know (the time
    /// span counts from retirement).
    public enum Kind: Hashable, Sendable, Codable {
        case retirement
        case pension
        case accessible
        case windfall
        case expense
    }

    public var date: Date
    public var label: String
    public var systemImage: String?
    public var kind: Kind?

    public init(date: Date, label: String, systemImage: String? = nil, kind: Kind? = nil) {
        self.date = date
        self.label = label
        self.systemImage = systemImage
        self.kind = kind
    }

    public var id: String { "\(date.timeIntervalSinceReferenceDate) \(label)" }
    /// Its icon: its own, or a small triangle.
    public var symbol: String { systemImage ?? "arrowtriangle.up.fill" }
}
