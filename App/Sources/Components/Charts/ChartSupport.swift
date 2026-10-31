import Accessibility
import Charts
import Model
import SwiftUI
import Tracker

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
    /// How VoiceOver reads an amount in a chart's audio graph and chart
    /// details: the full amount in the currency, or "Amount hidden" while
    /// amounts are hidden (`hidden`: the chart's
    /// `redactionReasons.hidesAmounts`), as its labels are.
    static func spokenAmount(currency: CurrencyCode, hidden: Bool) -> @Sendable (Double) -> String {
        guard hidden else {
            return { value in AmountFormat.amount(Decimal(wholeNumber: value), currency: currency) }
        }
        return { _ in spokenHiddenAmount }
    }

    /// What VoiceOver reads for an amount while amounts are hidden.
    static let spokenHiddenAmount = "Amount hidden"

    /// A share read as a percentage.
    static let spokenShare: @Sendable (Double) -> String = { value in
        AmountFormat.percent(value, digits: 0)
    }

    /// The width a chart assumes until it has measured itself.
    static let defaultWidth: CGFloat = 320

    /// The widest a chart's callout grows (``ChartCallout``).
    static let calloutWidth: CGFloat = 210
}

extension ChartContent {
    /// A mark that plots amounts, as VoiceOver reads it: Swift Charts reads
    /// each mark's plotted values, so while amounts are hidden (`hidden`: the
    /// chart's `redactionReasons.hidesAmounts`) its value is hidden, as the
    /// axis labels and the audio graph's values are
    /// (``ChartStyle/spokenAmount(currency:hidden:)``).
    @MainActor @ChartContentBuilder
    func spokenValueHidden(_ hidden: Bool) -> some ChartContent {
        if hidden {
            accessibilityValue(Text(verbatim: ChartStyle.spokenHiddenAmount))
        } else {
            self
        }
    }

    /// A mark as VoiceOver reads it: `spoken` in place of the value it's
    /// plotted at, such as a cut mark's real value (``ChartCut``); `nil`
    /// reads the plotted value.
    @MainActor @ChartContentBuilder
    func spokenValue(_ spoken: String?) -> some ChartContent {
        if let spoken {
            accessibilityValue(Text(verbatim: spoken))
        } else {
            self
        }
    }
}

// MARK: - Colours

extension Palette {
    /// The colour for a chart colour role: for washes and larger fills.
    static func color(for role: ChartColor) -> Color {
        switch role {
        case .assetClass(let assetClass): color(for: assetClass)
        case .debt: debt
        case .series(let index): series[min(max(index, 0), series.count - 1)]
        case .accent: accent
        case .ink: ink
        case .neutral: mutedInk
        // Validated against all eight series hues and their line steps in
        // both modes (CVD ΔE ≥ 10, normal vision ≥ 17, contrast ≥ 3:1); muted
        // ink isn't (ΔE 1–5 to aqua and magenta).
        case .taxes: secondaryInk
        }
    }

    /// The colour for a line, the edge along a stacked area, or a small mark
    /// (a legend swatch, a dot, a thin bar) in a chart colour role: the
    /// categorical slots' line steps (``seriesStroke``), so it reaches 3:1
    /// on the chart surface in light mode too; other roles as ``color(for:)``.
    static func stroke(for role: ChartColor) -> Color {
        switch role {
        case .assetClass(let assetClass): stroke(for: assetClass)
        case .series(let index): seriesStroke[min(max(index, 0), seriesStroke.count - 1)]
        default: color(for: role)
        }
    }
}

// MARK: - Axes
//
// Functions rather than custom `AxisContent` types: Swift Charts doesn't
// support conforming your own types to `AxisContent`.

/// The y axis of a chart with an ``AmountScale``: faint gridlines at the
/// scale's ticks, labelled compactly so no two read alike (never "−0"), on
/// the leading edge. While amounts are hidden (`hidesAmounts`: the chart's
/// `redactionReasons.hidesAmounts`) the labels would reveal them, so the
/// axis shows multiples of `base` instead (`0`, `1×`, `2×`: e.g. of today's
/// value), the one label left unredacted; without a base, the amounts draw
/// as placeholders (``AmountAxisTicks``). The chart sets
/// `.chartYScale(domain: scale.domain)` to match.
func amountAxis(hidesAmounts: Bool, scale: AmountScale, relativeTo base: Double? = nil) -> some AxisContent {
    let axis = AmountAxisTicks(scale: scale, hidesAmounts: hidesAmounts, relativeTo: base)
    return AxisMarks(position: .leading, values: axis.values) { value in
        AxisGridLine(stroke: StrokeStyle(lineWidth: 0.5))
            .foregroundStyle(Palette.gridline)
        AxisValueLabel {
            if let amount = value.as(Double.self) {
                AmountAxisLabel(text: axis.label(for: amount), isRelative: axis.isRelative)
            }
        }
    }
}

/// A value axis label (``amountAxis(hidesAmounts:scale:relativeTo:)``): an
/// amount draws as a placeholder while amounts are hidden. A multiple of a
/// base (`1×`) reveals no amount, so it's marked `.unredacted()` and reads
/// with the eye on: the one view of the person's data that is (UI.md,
/// "Privacy"). In a feedback screenshot (`hidesPersonalData`), which hides
/// all of a chart's text, it draws as a placeholder too.
struct AmountAxisLabel: View {
    let text: String
    let isRelative: Bool

    @Environment(\.hidesPersonalData) private var hidesPersonalData

    /// Nonisolated: `amountAxis` makes it in its axis's content.
    nonisolated init(text: String, isRelative: Bool) {
        self.text = text
        self.isRelative = isRelative
    }

    var body: some View {
        let label = Text(verbatim: text)
            .font(.caption2)
            .monospacedDigit()
            .foregroundStyle(Palette.mutedInk)
        if isRelative && !hidesPersonalData {
            label.unredacted()
        } else {
            label.privacySensitive()
        }
    }
}

/// An axis with a tick at each of `values`, its label from `label` in
/// caption 2 with tabular figures: the dates ``TimeTicks`` chose
/// (``dateAxis(_:)``), or the ages and years ``IntegerTicks`` chose, never
/// one per bar.
func tickAxis<Value: Plottable & Sendable>(_ values: [Value],
                                           label: @escaping @Sendable (Value) -> String) -> some AxisContent {
    AxisMarks(values: values) { value in
        AxisTick(stroke: StrokeStyle(lineWidth: 0.5))
            .foregroundStyle(Palette.axis)
        AxisValueLabel {
            if let typed = value.as(Value.self) {
                // Whole even at the chart's edge, where the last label would
                // otherwise be cut short ("2…").
                Text(verbatim: label(typed))
                    .font(.caption2)
                    .monospacedDigit()
                    .foregroundStyle(Palette.mutedInk)
                    .fixedSize()
            }
        }
    }
}

/// A time axis with the ticks ``TimeTicks`` chose for the chart's width:
/// years every 1, 2, 5 or 10…, or months, never more than fit.
func dateAxis(_ ticks: TimeTicks) -> some AxisContent {
    tickAxis(ticks.dates) { ticks.label(for: $0) }
}

extension Array where Element == ChartPoint {
    /// The point nearest to `date`.
    func nearest(to date: Date) -> ChartPoint? {
        self.min { abs($0.date.timeIntervalSince(date)) < abs($1.date.timeIntervalSince(date)) }
    }
}

extension View {
    /// Keeps `width` in step with the view's width, so a chart can fit its
    /// ticks and labels to the room it has. Whole points only, so a width
    /// that wobbles by a fraction while a window lays itself out doesn't
    /// redraw the chart (and change the layout) each time.
    func measuringWidth(_ width: Binding<CGFloat>) -> some View {
        onGeometryChange(for: CGFloat.self) { proxy in
            proxy.size.width.rounded()
        } action: { newWidth in
            if newWidth > 0, newWidth != width.wrappedValue { width.wrappedValue = newWidth }
        }
    }

    /// A chart callout's surface: the card's colour in a hairline border,
    /// with 8-point corners. After the callout's own padding and frame.
    func calloutBackground() -> some View {
        background(Palette.card, in: RoundedRectangle(cornerRadius: 8, style: .continuous))
            .overlay { RoundedRectangle(cornerRadius: 8, style: .continuous).strokeBorder(Palette.border) }
    }
}

// MARK: - Markers

/// Each marker's rule, from the bottom of the chart to the top of the data,
/// with its label above in the row ``MarkerLabelLayout`` chose, or only its
/// icon: a time chart's markers (retirement, pension starts, …). The top of
/// the data is an amount, hidden from VoiceOver with `hidesAmounts` (the
/// chart's `redactionReasons.hidesAmounts`).
@MainActor @ChartContentBuilder
func markerRules(_ markers: MarkerLabelLayout, scale: AmountScale, hidesAmounts: Bool) -> some ChartContent {
    ForEach(markers.placements) { placement in
        RuleMark(x: .value("Date", placement.marker.date),
                 yStart: .value("Bottom", scale.domain.lowerBound),
                 yEnd: .value("Top", scale.dataTop))
            .foregroundStyle(Palette.axis)
            .lineStyle(StrokeStyle(lineWidth: 1))
            .annotation(position: .top, alignment: placement.alignment,
                        spacing: 2 + CGFloat(placement.row) * CGFloat(ChartText.rowHeight),
                        overflowResolution: .init(x: .fit(to: .chart), y: .fit(to: .chart))) {
                ChartMarkerLabel(placement: placement)
            }
            .spokenValueHidden(hidesAmounts)
    }
}

extension MarkerLabelLayout.Placement {
    /// The label against its rule: after it, or ending at it at the chart's
    /// right edge; only the icon, centred on it.
    var alignment: Alignment {
        showsLabel ? (endsAtRule ? .trailing : .leading) : .center
    }
}

/// A marker's label above the data: its icon and words, or only the icon
/// when there's no room (the words are then in the callout).
struct ChartMarkerLabel: View {
    let placement: MarkerLabelLayout.Placement

    var body: some View {
        Group {
            if placement.showsLabel {
                Label(placement.marker.label, systemImage: placement.marker.symbol)
                    .labelStyle(.titleAndIcon)
                    .lineLimit(1)
                    .fixedSize()
            } else {
                Image(systemName: placement.marker.symbol)
                    .accessibilityLabel(placement.marker.label)
            }
        }
        .font(.caption2)
        .foregroundStyle(Palette.secondaryInk)
        .privacySensitiveInFeedback()
    }
}

// MARK: - Legend, captions

/// What a legend item's swatch looks like: it mirrors the mark.
enum ChartSwatch: Hashable {
    /// A line, solid or dashed.
    case line(ChartColor, dashed: Bool)
    /// A dotted line.
    case dottedLine(ChartColor)
    /// A wash of the colour with a line along its top: a stacked area
    /// drawn as a wash with its edge.
    case wash(ChartColor)
    /// A band of the accent colour at an opacity.
    case band(opacity: Double)
    /// A bar of the colour.
    case bar(ChartColor)
    /// A bar of the colour, hatched (``ChartHatch``).
    case hatchedBar(ChartColor)
    /// A bar of the colour at an opacity: a lighter part of a stacked bar.
    case fadedBar(ChartColor, opacity: Double)
    /// A dot of the colour.
    case dot(ChartColor)
}

/// Diagonal stripes of a colour, for a bar that holds more than its period:
/// the colour, and a faint step of it between.
enum ChartHatch {
    /// How many stripes cross the mark.
    static let stripes = 20

    /// How strong the faint stripes are against the colour.
    static let faintOpacity = 0.3

    static func style(_ color: Color) -> LinearGradient {
        var stops: [Gradient.Stop] = []
        let width = 1 / Double(stripes)
        for index in 0..<stripes {
            let start = Double(index) * width
            stops.append(Gradient.Stop(color: color, location: start))
            stops.append(Gradient.Stop(color: color, location: start + width / 2))
            stops.append(Gradient.Stop(color: color.opacity(faintOpacity), location: start + width / 2))
            stops.append(Gradient.Stop(color: color.opacity(faintOpacity), location: start + width))
        }
        return LinearGradient(stops: stops, startPoint: .topLeading, endPoint: .bottomTrailing)
    }
}

/// A bar, dot or line beyond the value axis, drawn to its edge: a bar is
/// broken by a gap in the chart's surface a little inside the edge, a dot
/// becomes a triangle pointing past it, and a line runs along the edge with
/// a triangle at each point past it.
enum ChartCut {
    /// How far inside the edge a bar's gap is, as a share of the axis.
    static let inset = 0.06

    /// Where `value`'s bar is broken when it's beyond `domain`; `nil` when
    /// it fits.
    static func gap(_ value: Double, within domain: ClosedRange<Double>) -> Double? {
        let inset = (domain.upperBound - domain.lowerBound) * Self.inset
        if value > domain.upperBound { return domain.upperBound - inset }
        if value < domain.lowerBound { return domain.lowerBound + inset }
        return nil
    }

    /// The gap across a cut bar, from `start` to `end`, at `y`, in the
    /// surface's colour. VoiceOver skips it: the bar's marks read the
    /// value.
    @ChartContentBuilder
    static func gapMark(from start: Date, to end: Date, at y: Double, surface: Color) -> some ChartContent {
        RuleMark(xStart: .value("Date", start), xEnd: .value("Date", end), y: .value("Cut", y))
            .foregroundStyle(surface)
            .lineStyle(StrokeStyle(lineWidth: 2))
            .accessibilityHidden(true)
    }

    /// The triangle a cut dot is drawn as, pointing up past the top or down
    /// past the bottom.
    static func arrow(up: Bool, color: Color) -> some View {
        Image(systemName: up ? "arrowtriangle.up.fill" : "arrowtriangle.down.fill")
            .font(.system(size: 8))
            .foregroundStyle(color)
    }
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
/// doesn't fit. `note` follows the items, e.g. "↑ Bands continue above".
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
                FlowRows {
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
        .privacySensitiveInFeedback()
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
            .stroke(Palette.stroke(for: color),
                    style: StrokeStyle(lineWidth: 2, lineCap: .round, dash: dashed ? [3, 2] : []))
        case .dottedLine(let color):
            Path { path in
                path.move(to: CGPoint(x: 1, y: 5))
                path.addLine(to: CGPoint(x: 14, y: 5))
            }
            .stroke(Palette.stroke(for: color), style: StrokeStyle(lineWidth: 2, lineCap: .round, dash: [0.5, 3.5]))
        case .wash(let color):
            ZStack(alignment: .top) {
                Rectangle()
                    .fill(Palette.color(for: color).opacity(IncomeChartData.fillOpacity))
                Rectangle()
                    .fill(Palette.stroke(for: color))
                    .frame(height: 2)
            }
        case .band(let opacity):
            RoundedRectangle(cornerRadius: 2, style: .continuous)
                .fill(Palette.accent.opacity(opacity))
        case .bar(let color):
            RoundedRectangle(cornerRadius: 2, style: .continuous)
                .fill(Palette.color(for: color))
                .frame(width: 8)
        case .hatchedBar(let color):
            RoundedRectangle(cornerRadius: 2, style: .continuous)
                .fill(ChartHatch.style(Palette.color(for: color)))
                .frame(width: 8)
        case .fadedBar(let color, let opacity):
            RoundedRectangle(cornerRadius: 2, style: .continuous)
                .fill(Palette.color(for: color).opacity(opacity))
                .frame(width: 8)
        case .dot(let color):
            Circle()
                .fill(Palette.stroke(for: color))
                .frame(width: 7, height: 7)
        }
    }
}

/// The legend of a projection: your actual values, the median and the two
/// bands, with a cue when a band runs off the top.
struct ProjectionLegend: View {
    var showsActual = true
    /// Today draws the projected median dashed after a solid history.
    var dashedMedian = false
    var clipsBand = false

    /// The bands' opacities, shared with the charts.
    static let innerBand = 0.28
    static let outerBand = 0.14

    var body: some View {
        ChartLegendRow(items: items, note: clipsBand ? "↑ Bands continue above" : nil)
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

/// One control for a chart's time span (UI.md, "Today"): how far back
/// (1Y, 3Y, 5Y, All) and, while the future is shown, how far ahead (to
/// retirement, or retirement + 5, 10, 20 or 30 years; once retirement is
/// behind, 5, 10, 20 or 30 years from today).
struct TimeSpanMenu: View {
    @Binding var range: HistoryRange
    /// The horizon in use, `nil` while the future isn't shown (see
    /// ``AppPreferences/horizonBinding(start:retirement:)``).
    var horizon: Binding<FutureHorizon>?
    /// The horizons that make sense for the plan
    /// (``FutureHorizon/choices(start:retirement:)``).
    var choices: [FutureHorizon]
    /// A shorter label, for an iPhone.
    var compact = false

    var body: some View {
        Menu {
            Section("History") {
                Picker("History", selection: $range) {
                    ForEach(HistoryRange.allCases, id: \.self) { option in
                        Text(option.menuTitle).tag(option)
                    }
                }
                .pickerStyle(.inline)
            }
            if let horizon {
                Section("Future") {
                    Picker("Future", selection: horizon) {
                        ForEach(choices, id: \.self) { option in
                            Text(option.title(fromRetirement: fromRetirement)).tag(option)
                        }
                    }
                    .pickerStyle(.inline)
                }
            }
        } label: {
            Label(timeSpanTitle(range: range, horizon: horizon?.wrappedValue, fromRetirement: fromRetirement,
                                compact: compact),
                  systemImage: "calendar")
                .font(.subheadline)
                .monospacedDigit()
        }
        .fixedSize()
        .accessibilityLabel("Time span")
        .accessibilityValue(accessibilityValue)
    }

    /// Whether the horizons count from retirement: while *To retirement*
    /// is offered, that is while retirement is ahead.
    private var fromRetirement: Bool {
        choices.contains(.toRetirement)
    }

    private var accessibilityValue: String {
        guard let horizon else { return range.spokenTitle }
        let title = horizon.wrappedValue.title(fromRetirement: fromRetirement)
        return "\(range.spokenTitle) back, \(title.lowercased()) ahead"
    }
}

extension AppPreferences {
    /// The future horizon as the time span menu shows and sets it: the
    /// horizon in use (*To retirement* becomes the standard horizon once
    /// retirement isn't ahead); a choice is remembered.
    func horizonBinding(start: Date, retirement: Date?) -> Binding<FutureHorizon> {
        Binding(get: { self.futureHorizon.effective(start: start, retirement: retirement) },
                set: { self.futureHorizon = $0 })
    }
}

extension HistoryRange {
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
