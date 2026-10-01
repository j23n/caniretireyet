import Accessibility
import Charts
import Model
import SwiftUI

/// A VoiceOver summary of a chart (UI.md: every chart has one, through
/// `accessibilityChartDescriptor`). Built from plain numbers, so every chart
/// component makes one the same way.
struct ChartSummary: AXChartDescriptorRepresentable {
    /// One series: a name and its points.
    struct Series {
        var name: String
        /// (x label, y value); the x labels are read as categories.
        var points: [(String, Double)]
    }

    var title: String
    var summary: String
    var xTitle: String
    var yTitle: String
    var series: [Series]
    /// How a y value is read, e.g. "312 thousand euros".
    var describeValue: @Sendable (Double) -> String

    func makeChartDescriptor() -> AXChartDescriptor {
        let values = series.flatMap { $0.points.map(\.1) }
        let low = min(values.min() ?? 0, 0)
        let high = max(values.max() ?? 1, low + 1)
        let categories = series.first?.points.map(\.0) ?? []
        let describe = describeValue
        let xAxis = AXCategoricalDataAxisDescriptor(title: xTitle, categoryOrder: categories)
        let yAxis = AXNumericDataAxisDescriptor(title: yTitle, range: low...high, gridlinePositions: []) { value in
            describe(value)
        }
        let descriptors = series.map { series in
            AXDataSeriesDescriptor(
                name: series.name, isContinuous: true,
                dataPoints: series.points.map { AXDataPoint(x: $0.0, y: $0.1) })
        }
        return AXChartDescriptor(title: title, summary: summary, xAxis: xAxis, yAxis: yAxis, additionalAxes: [],
                                 series: descriptors)
    }
}

/// Shared chart styling: faint grid, muted axis labels, compact numbers.
enum ChartStyle {
    /// How VoiceOver reads a chart value: the full amount in the currency.
    static func spokenAmount(currency: CurrencyCode) -> @Sendable (Double) -> String {
        { value in
            AmountFormat.amount(Decimal(Int(value.rounded())), currency: currency)
        }
    }

    /// A share read as a percentage.
    static let spokenShare: @Sendable (Double) -> String = { value in
        AmountFormat.percent(value, digits: 0)
    }
}

/// The y axis most charts use: faint gridlines and compact labels (`312k`)
/// on the leading edge, or nothing while amounts are hidden.
///
/// A function rather than a custom `AxisContent` type: Swift Charts doesn't
/// support conforming your own types to `AxisContent`.
func amountAxis(hidesAmounts: Bool, desiredCount: Int = 4) -> some AxisContent {
    AxisMarks(position: .leading, values: .automatic(desiredCount: desiredCount)) { value in
        AxisGridLine(stroke: StrokeStyle(lineWidth: 0.5))
            .foregroundStyle(Palette.gridline)
        AxisValueLabel {
            if let amount = value.as(Double.self) {
                Text(verbatim: hidesAmounts ? "" : AmountFormat.compact(amount))
                    .font(.caption2)
                    .monospacedDigit()
                    .foregroundStyle(Palette.mutedInk)
            }
        }
    }
}

/// The y axis of a chart with an ``AmountScale``: faint gridlines at the
/// scale's ticks, labelled compactly so no two read alike (never "−0"), on
/// the leading edge, or no labels while amounts are hidden. The chart sets
/// `.chartYScale(domain: scale.domain)` to match.
func amountAxis(hidesAmounts: Bool, scale: AmountScale) -> some AxisContent {
    AxisMarks(position: .leading, values: scale.ticks) { value in
        AxisGridLine(stroke: StrokeStyle(lineWidth: 0.5))
            .foregroundStyle(Palette.gridline)
        AxisValueLabel {
            if let amount = value.as(Double.self) {
                Text(verbatim: hidesAmounts ? "" : scale.label(amount))
                    .font(.caption2)
                    .monospacedDigit()
                    .foregroundStyle(Palette.mutedInk)
            }
        }
    }
}

/// The date axis most charts use: a few year or month labels, no grid.
/// `spansYears` chooses year labels over month labels.
func dateAxis(spansYears: Bool, desiredCount: Int = 4) -> some AxisContent {
    let style = spansYears ? Date.FormatStyle.dateTime.year() : Date.FormatStyle.dateTime.month(.abbreviated)
    return AxisMarks(values: .automatic(desiredCount: desiredCount)) { value in
        AxisTick(stroke: StrokeStyle(lineWidth: 0.5))
            .foregroundStyle(Palette.axis)
        AxisValueLabel {
            if let date = value.as(Date.self) {
                Text(date, format: style)
                    .font(.caption2)
                    .foregroundStyle(Palette.mutedInk)
            }
        }
    }
}

extension Array where Element == ChartPoint {
    /// Whether the points span more than about 18 months.
    var spansYears: Bool {
        guard let first = first?.date, let last = last?.date else { return false }
        return last.timeIntervalSince(first) > 86_400 * 540
    }

    /// The point nearest to `date`.
    func nearest(to date: Date) -> ChartPoint? {
        self.min { abs($0.date.timeIntervalSince(date)) < abs($1.date.timeIntervalSince(date)) }
    }
}
