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

    /// The width a chart assumes until it has measured itself.
    static let defaultWidth: CGFloat = 320
}

// MARK: - Axes
//
// Functions rather than custom `AxisContent` types: Swift Charts doesn't
// support conforming your own types to `AxisContent`.

/// The y axis of a chart with an ``AmountScale``: faint gridlines at the
/// scale's ticks, labelled compactly so no two read alike (never "−0"), on
/// the leading edge. While amounts are hidden the labels would reveal them,
/// so the axis shows multiples of `base` instead (`0`, `1×`, `2×`: e.g. of
/// today's value), or no labels without a base. The chart sets
/// `.chartYScale(domain: scale.domain)` to match.
func amountAxis(hidesAmounts: Bool, scale: AmountScale, relativeTo base: Double? = nil) -> some AxisContent {
    let relative = hidesAmounts ? scale.relativeTicks(base: base ?? 0) : []
    let values = hidesAmounts && !relative.isEmpty ? relative.map(\.value) : scale.ticks
    return AxisMarks(position: .leading, values: values) { value in
        AxisGridLine(stroke: StrokeStyle(lineWidth: 0.5))
            .foregroundStyle(Palette.gridline)
        AxisValueLabel {
            if let amount = value.as(Double.self) {
                Text(verbatim: amountLabel(amount, hidesAmounts: hidesAmounts, scale: scale, relative: relative))
                    .font(.caption2)
                    .monospacedDigit()
                    .foregroundStyle(Palette.mutedInk)
            }
        }
    }
}

/// A value axis label: the compact amount, or while amounts are hidden the
/// relative tick's label (nothing without one).
private func amountLabel(_ amount: Double, hidesAmounts: Bool, scale: AmountScale, relative: [RelativeTick]) -> String {
    guard hidesAmounts else { return scale.label(amount) }
    let tolerance = max(abs(amount), 1) * 1e-6
    return relative.first { abs($0.value - amount) <= tolerance }?.label ?? ""
}

/// A time axis with the ticks ``TimeTicks`` chose for the chart's width:
/// years every 1, 2, 5 or 10…, or months, never more than fit.
func dateAxis(_ ticks: TimeTicks) -> some AxisContent {
    AxisMarks(values: ticks.dates) { value in
        AxisTick(stroke: StrokeStyle(lineWidth: 0.5))
            .foregroundStyle(Palette.axis)
        AxisValueLabel {
            if let date = value.as(Date.self) {
                Text(verbatim: ticks.label(for: date))
                    .font(.caption2)
                    .monospacedDigit()
                    .foregroundStyle(Palette.mutedInk)
            }
        }
    }
}

/// A year axis for charts whose x is a year number (`Double`), with the
/// years ``IntegerTicks`` chose: every 5 or 10 years, never one per bar.
func yearAxis(_ years: [Int]) -> some AxisContent {
    AxisMarks(values: years.map(Double.init)) { value in
        AxisTick(stroke: StrokeStyle(lineWidth: 0.5))
            .foregroundStyle(Palette.axis)
        AxisValueLabel {
            if let year = value.as(Double.self) {
                Text(verbatim: String(Int(year.rounded())))
                    .font(.caption2)
                    .monospacedDigit()
                    .foregroundStyle(Palette.mutedInk)
            }
        }
    }
}

/// An age axis (`Int`), with the ages ``IntegerTicks`` chose: every 5
/// (or 2, or 10) as the width allows.
func ageAxis(_ ages: [Int]) -> some AxisContent {
    AxisMarks(values: ages) { value in
        AxisTick(stroke: StrokeStyle(lineWidth: 0.5))
            .foregroundStyle(Palette.axis)
        AxisValueLabel {
            if let age = value.as(Int.self) {
                Text(verbatim: String(age))
                    .font(.caption2)
                    .monospacedDigit()
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

extension View {
    /// Keeps `width` in step with the view's width, so a chart can fit its
    /// ticks and labels to the room it has.
    func measuringWidth(_ width: Binding<CGFloat>) -> some View {
        onGeometryChange(for: CGFloat.self) { proxy in
            proxy.size.width
        } action: { newWidth in
            if newWidth > 0 { width.wrappedValue = newWidth }
        }
    }
}

// MARK: - Markers

/// A marker's label above the data: its icon and words, or only the icon
/// when there's no room (the words are then in the callout).
struct ChartMarkerLabel: View {
    let placement: MarkerLabelLayout.Placement

    var body: some View {
        Group {
            if placement.showsLabel {
                Label(placement.marker.label, systemImage: placement.marker.systemImage ?? "arrowtriangle.up.fill")
                    .labelStyle(.titleAndIcon)
                    .lineLimit(1)
                    .fixedSize()
            } else {
                Image(systemName: placement.marker.systemImage ?? "arrowtriangle.up.fill")
                    .accessibilityLabel(placement.marker.label)
            }
        }
        .font(.caption2)
        .foregroundStyle(Palette.secondaryInk)
    }
}

// MARK: - Legend, captions

/// What a legend item's swatch looks like: it mirrors the mark.
enum ChartSwatch: Hashable {
    /// A line, solid or dashed.
    case line(ChartColor, dashed: Bool)
    /// A filled area or bar.
    case area(ChartColor)
    /// A wash of the colour with a line along its top: a stacked area
    /// drawn as a wash with its edge.
    case wash(ChartColor)
    /// A band of the accent colour at an opacity.
    case band(opacity: Double)
}

/// One item of a chart's legend.
struct ChartLegendItem: Hashable, Identifiable {
    var name: String
    var swatch: ChartSwatch

    var id: String { name }
}

/// A chart's legend, in a row of its own above the chart (UI.md,
/// "Charts"): each item a swatch that mirrors its mark and a name in a text
/// token, never in the series colour. It wraps onto more rows when it
/// doesn't fit. `note` follows the items, e.g. "↑ 10–90% continues above".
struct ChartLegendRow: View {
    var items: [ChartLegendItem]
    var note: String?

    var body: some View {
        ViewThatFits(in: .horizontal) {
            HStack(spacing: Metrics.m) {
                ForEach(items) { item in
                    ChartLegendLabel(item: item)
                }
                if let note {
                    Text(note)
                        .foregroundStyle(Palette.mutedInk)
                }
            }
            .fixedSize()
            VStack(alignment: .leading, spacing: Metrics.xs) {
                LazyVGrid(columns: [GridItem(.adaptive(minimum: 104), spacing: Metrics.m, alignment: .leading)],
                          alignment: .leading, spacing: Metrics.xs) {
                    ForEach(items) { item in
                        ChartLegendLabel(item: item)
                    }
                }
                if let note {
                    Text(note)
                        .foregroundStyle(Palette.mutedInk)
                }
            }
        }
        .font(.caption)
        .foregroundStyle(Palette.secondaryInk)
        .accessibilityElement(children: .combine)
    }
}

/// A legend item: its swatch and name.
struct ChartLegendLabel: View {
    let item: ChartLegendItem

    var body: some View {
        HStack(spacing: Metrics.xs) {
            swatch
                .frame(width: 14, height: 10)
            Text(item.name)
                .lineLimit(1)
        }
    }

    @ViewBuilder
    private var swatch: some View {
        switch item.swatch {
        case .line(let color, let dashed):
            Path { path in
                path.move(to: CGPoint(x: 0, y: 5))
                path.addLine(to: CGPoint(x: 14, y: 5))
            }
            .stroke(Palette.color(for: color),
                    style: StrokeStyle(lineWidth: 2, lineCap: .round, dash: dashed ? [3, 2] : []))
        case .area(let color):
            RoundedRectangle(cornerRadius: 2, style: .continuous)
                .fill(Palette.color(for: color))
        case .wash(let color):
            ZStack(alignment: .top) {
                Rectangle()
                    .fill(Palette.color(for: color).opacity(IncomeChartData.fillOpacity))
                Rectangle()
                    .fill(Palette.color(for: color))
                    .frame(height: 2)
            }
        case .band(let opacity):
            RoundedRectangle(cornerRadius: 2, style: .continuous)
                .fill(Palette.accent.opacity(opacity))
        }
    }
}

/// The legend of a projection: your actual values, the median and the two
/// bands, with a cue when the 10–90% band runs off the top.
struct ProjectionLegend: View {
    var showsActual = true
    /// The Overview draws the projected median dashed after a solid history.
    var dashedMedian = false
    var clipsBand = false

    /// The bands' opacities, shared with the charts.
    static let innerBand = 0.28
    static let outerBand = 0.14

    var body: some View {
        ChartLegendRow(items: items, note: clipsBand ? "↑ 10–90% continues above" : nil)
    }

    private var items: [ChartLegendItem] {
        var items: [ChartLegendItem] = []
        if showsActual {
            items.append(ChartLegendItem(name: "Actual", swatch: .line(.ink, dashed: false)))
        }
        items.append(ChartLegendItem(name: "Median", swatch: .line(.accent, dashed: dashedMedian)))
        items.append(ChartLegendItem(name: "25–75%", swatch: .band(opacity: Self.innerBand)))
        items.append(ChartLegendItem(name: "10–90%", swatch: .band(opacity: Self.outerBand)))
        return items
    }
}

/// A short caption under a chart with an ⓘ that shows the full explanation
/// in a popover, instead of a paragraph under the chart.
struct ChartCaption: View {
    let text: String
    let detail: String
    @State private var showsDetail = false

    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: Metrics.xs) {
            Text(text)
                .font(.footnote)
                .foregroundStyle(Palette.secondaryInk)
                .fixedSize(horizontal: false, vertical: true)
            Button {
                showsDetail = true
            } label: {
                Image(systemName: "info.circle")
                    .font(.footnote)
            }
            .buttonStyle(.borderless)
            .accessibilityLabel("About this chart")
            .popover(isPresented: $showsDetail) {
                Text(detail)
                    .font(.callout)
                    .foregroundStyle(Palette.ink)
                    .fixedSize(horizontal: false, vertical: true)
                    .padding(Metrics.l)
                    .frame(idealWidth: 320, maxWidth: 360, alignment: .leading)
                    .presentationCompactAdaptation(.popover)
            }
        }
    }
}

// MARK: - Time span

/// One control for a chart's time span (UI.md, "Overview"): how far back
/// (1Y, 3Y, 5Y, All) and, while the future is shown, how far ahead (to
/// retirement, retirement + 15 years, 20 years, the whole plan).
struct TimeSpanMenu: View {
    @Binding var range: OverviewRange
    /// The horizon in use, `nil` while the future isn't shown (see
    /// ``AppPreferences/horizonBinding(start:retirement:)``).
    var horizon: Binding<FutureHorizon>?
    /// The horizons that make sense for the plan.
    var choices: [FutureHorizon] = FutureHorizon.allCases
    /// A shorter label, for an iPhone.
    var compact = false

    var body: some View {
        Menu {
            Section("History") {
                Picker("History", selection: $range) {
                    ForEach(OverviewRange.allCases, id: \.self) { option in
                        Text(option.menuTitle).tag(option)
                    }
                }
                .pickerStyle(.inline)
            }
            if let horizon {
                Section("Future") {
                    Picker("Future", selection: horizon) {
                        ForEach(choices, id: \.self) { option in
                            Text(option.title).tag(option)
                        }
                    }
                    .pickerStyle(.inline)
                }
            }
        } label: {
            Label(timeSpanTitle(range: range, horizon: horizon?.wrappedValue, compact: compact),
                  systemImage: "calendar")
                .font(.subheadline)
                .monospacedDigit()
        }
        .fixedSize()
        .accessibilityLabel("Time span")
        .accessibilityValue(accessibilityValue)
    }

    private var accessibilityValue: String {
        guard let horizon else { return range.spokenTitle }
        return "\(range.spokenTitle) back, \(horizon.wrappedValue.title.lowercased()) ahead"
    }
}

extension AppPreferences {
    /// The future horizon as the time span menu shows and sets it: the
    /// horizon in use (a retirement-based one becomes 20 years once
    /// retirement isn't ahead); a choice is remembered.
    func horizonBinding(start: Date, retirement: Date?) -> Binding<FutureHorizon> {
        Binding(get: { self.futureHorizon.effective(start: start, retirement: retirement) },
                set: { self.futureHorizon = $0 })
    }
}

extension OverviewRange {
    /// In the time span menu: "Last year", "Last 3 years", "All".
    var menuTitle: String {
        switch self {
        case .oneYear: "Last year"
        case .threeYears: "Last 3 years"
        case .fiveYears: "Last 5 years"
        case .all: "All history"
        }
    }
}
