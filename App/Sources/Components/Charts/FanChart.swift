import Charts
import Model
import SwiftUI
import Tracker

/// A projection with its uncertainty (UI.md, "Your money over time"): the
/// median line, a darker 25–75% band and a lighter 10–90% band, all in one
/// hue. Uncertainty is always a band, never just the median.
///
/// - `actual` draws your real past values as a solid line in ink, so "what
///   happened" never looks like "what was projected" (Progress: actual vs
///   baseline; *Future* history); dashed and grey where a total is partial.
/// - `markers` label retirement, locked money becoming accessible, pension
///   starts, windfalls and large expenses above the data, staggered in up
///   to two rows so they never collide (``MarkerLabelLayout``); a marker
///   without room shows its icon, with its label in the callout.
/// - With `showsLegend`, the legend sits in its own row above the chart,
///   and the value axis fits the history, the median and the 25–75% band:
///   the 10–90% band may run off the top, which the legend says
///   (``ProjectionScale``). Without it (a legend of the caller's own), the
///   axis fits every band.
/// - While amounts are hidden the axis reads in multiples of the start
///   value (today's plan assets).
/// - Drag across it to read the percentiles at any date.
struct FanChart: View {
    var fan: [FanPoint]
    var actual: [ChartPoint] = []
    var markers: [ChartMarker] = []
    /// `nil` for the base currency.
    var currency: CurrencyCode?
    var showsLegend = false

    @State private var selectedDate: Date?
    @State private var width: CGFloat = ChartStyle.defaultWidth
    @Environment(\.hidesAmounts) private var hidesAmounts
    @Environment(\.baseCurrency) private var baseCurrency

    private static let height: CGFloat = 240

    var body: some View {
        if fan.isEmpty {
            ChartPlaceholder(text: "The projection appears here once the plan has run.", height: Self.height)
        } else {
            let layout = self.layout
            VStack(alignment: .leading, spacing: Metrics.s) {
                if showsLegend {
                    ProjectionLegend(showsActual: !actual.isEmpty, clipsBand: layout.clipsBand)
                }
                chart(layout)
                    .frame(height: Self.height)
                    .measuringWidth($width)
                    .accessibilityChartDescriptor(summary)
            }
        }
    }

    /// Everything placed for the chart's width and height: the value axis
    /// fits the complete actual values, and the median and 25–75% band, or
    /// without a legend every band.
    private var layout: ProjectionLayout {
        ProjectionLayout(dates: fan.map(\.date) + actual.map(\.date),
                         values: actual.filter(\.isComplete).map(\.value), fan: fan, fitsBands: !showsLegend,
                         markers: markers, width: Double(width), height: Double(Self.height))
    }

    private func chart(_ layout: ProjectionLayout) -> some View {
        Chart {
            ForEach(layout.fan) { point in
                AreaMark(x: .value("Date", point.date), yStart: .value("10th percentile", point.p10),
                         yEnd: .value("90th percentile", point.p90), series: .value("Series", "10–90%"))
                    .foregroundStyle(Palette.accent.opacity(ProjectionLegend.outerBand))
                    .interpolationMethod(.monotone)
                    .spokenValueHidden(hidesAmounts)
                AreaMark(x: .value("Date", point.date), yStart: .value("25th percentile", point.p25),
                         yEnd: .value("75th percentile", point.p75), series: .value("Series", "25–75%"))
                    .foregroundStyle(Palette.accent.opacity(ProjectionLegend.innerBand))
                    .interpolationMethod(.monotone)
                    .spokenValueHidden(hidesAmounts)
                LineMark(x: .value("Date", point.date), y: .value("Median", point.p50), series: .value("Series", "Median"))
                    .foregroundStyle(Palette.accent)
                    .lineStyle(StrokeStyle(lineWidth: Metrics.lineWidth, lineCap: .round, lineJoin: .round))
                    .interpolationMethod(.monotone)
                    .spokenValueHidden(hidesAmounts)
            }

            // Dashed and grey where a past total is partial (a price or rate missing).
            ForEach(actual.segments) { segment in
                ForEach(segment.points) { point in
                    LineMark(x: .value("Date", point.date), y: .value("Actual", point.value),
                             series: .value("Series", "Actual \(segment.id)"))
                        .foregroundStyle(segment.isComplete ? Palette.ink : Palette.secondaryInk)
                        .lineStyle(segment.isComplete
                            ? StrokeStyle(lineWidth: Metrics.lineWidth, lineCap: .round, lineJoin: .round)
                            : StrokeStyle(lineWidth: Metrics.lineWidth, lineCap: .round, lineJoin: .round, dash: [3, 4]))
                        .spokenValueHidden(hidesAmounts)
                }
            }

            markerRules(layout.markers, scale: layout.scale, hidesAmounts: hidesAmounts)

            if let selected = selectedPoint {
                RuleMark(x: .value("Date", selected.date))
                    .foregroundStyle(Palette.secondaryInk)
                    .lineStyle(StrokeStyle(lineWidth: 1))
                    .annotation(position: .top, spacing: 4,
                                overflowResolution: .init(x: .fit(to: .chart), y: .fit(to: .chart))) {
                        callout(for: selected, layout: layout)
                    }
            }
        }
        .chartXSelection(value: $selectedDate)
        .chartXScale(domain: layout.domain)
        .chartYScale(domain: layout.scale.domain)
        .chartYAxis { amountAxis(hidesAmounts: hidesAmounts, scale: layout.scale, relativeTo: fan.first?.p50) }
        .chartXAxis { dateAxis(layout.ticks) }
        .chartLegend(.hidden)
    }

    private var selectedPoint: FanPoint? {
        guard let selectedDate else { return nil }
        return fan.min { abs($0.date.timeIntervalSince(selectedDate)) < abs($1.date.timeIntervalSince(selectedDate)) }
    }

    private func callout(for point: FanPoint, layout: ProjectionLayout) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(point.date, format: .dateTime.year())
                .font(.caption2)
                .foregroundStyle(Palette.secondaryInk)
            row("9 in 10 above", point.p10)
            row("Median", point.p50)
            row("1 in 10 above", point.p90)
            ForEach(layout.markers.iconOnly(near: point.date)) { marker in
                Label(marker.label, systemImage: marker.symbol)
                    .font(.caption2)
                    .foregroundStyle(Palette.secondaryInk)
            }
        }
        .padding(Metrics.s)
        .calloutBackground()
    }

    private func row(_ label: String, _ value: Double) -> some View {
        HStack(spacing: Metrics.s) {
            Text(label).font(.caption2).foregroundStyle(Palette.secondaryInk)
            Spacer(minLength: Metrics.s)
            AmountText(Decimal(wholeNumber: value), currency: currency).font(.caption2.weight(.semibold))
        }
        .frame(width: 180)
    }

    private var summary: ChartSummary {
        let resolved = currency ?? baseCurrency
        let points = fan.map { (String(Calendar.current.component(.year, from: $0.date)), $0.p50) }
        var text = "Projected portfolio: the median, with a band from the 10th to the 90th percentile."
        if let last = fan.last, !hidesAmounts {
            text += " At the end, the median is \(AmountFormat.amount(Decimal(wholeNumber: last.p50), currency: resolved)); "
                + "in 9 of 10 simulated futures it's above "
                + "\(AmountFormat.amount(Decimal(wholeNumber: last.p10), currency: resolved))."
        }
        if !markers.isEmpty {
            text += " Marked: \(markers.map(\.label).joined(separator: ", "))."
        }
        return ChartSummary(
            title: "Your money over time", summary: text, xTitle: "Year", yTitle: "Portfolio",
            series: [ChartSummary.Series(name: "Median", points: points)],
            describeValue: ChartStyle.spokenAmount(currency: resolved, hidden: hidesAmounts))
    }
}

#Preview("Fan chart") {
    PreviewResultsView { results in
        let actual = PreviewLibrary.valuator.series(.planAssets, through: PreviewLibrary.latestCheckIn).chartPoints
        Card("Your money over time · whole plan") {
            FanChart(fan: results.portfolio, actual: actual, markers: results.markers, showsLegend: true)
        }
        Card("Retirement + 15 years") {
            let window = ProjectionWindow(now: PreviewLibrary.latestCheckIn.dateValue, range: .fiveYears,
                                          horizon: .retirementPlus15, retirement: results.retirementDate,
                                          planEnd: results.portfolio.last?.date ?? Date())
            FanChart(fan: window.fan(results.portfolio), actual: window.history(actual),
                     markers: window.markers(results.markers), showsLegend: true)
        }
        Card("Amounts hidden") {
            FanChart(fan: results.portfolio, actual: actual, markers: results.markers, showsLegend: true)
                .environment(\.hidesAmounts, true)
        }
    }
}
