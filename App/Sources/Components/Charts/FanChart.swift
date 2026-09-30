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
///   baseline; *Future* history).
/// - `markers` label retirement, locked money becoming accessible, pension
///   starts, windfalls and large expenses along the time axis.
/// - Drag across it to read the percentiles at any date.
struct FanChart: View {
    var fan: [FanPoint]
    var actual: [ChartPoint] = []
    var markers: [ChartMarker] = []
    /// `nil` for the base currency.
    var currency: CurrencyCode?
    var height: CGFloat = 240

    @State private var selectedDate: Date?
    @Environment(\.hidesAmounts) private var hidesAmounts
    @Environment(\.baseCurrency) private var baseCurrency

    var body: some View {
        if fan.isEmpty {
            ChartPlaceholder(text: "The projection appears here once the plan has run.", height: height)
        } else {
            chart
                .frame(height: height)
                .accessibilityChartDescriptor(summary)
        }
    }

    private var chart: some View {
        Chart {
            ForEach(fan) { point in
                AreaMark(x: .value("Date", point.date), yStart: .value("10th percentile", point.p10),
                         yEnd: .value("90th percentile", point.p90), series: .value("Series", "10–90%"))
                    .foregroundStyle(Palette.accent.opacity(0.14))
                    .interpolationMethod(.monotone)
                AreaMark(x: .value("Date", point.date), yStart: .value("25th percentile", point.p25),
                         yEnd: .value("75th percentile", point.p75), series: .value("Series", "25–75%"))
                    .foregroundStyle(Palette.accent.opacity(0.28))
                    .interpolationMethod(.monotone)
                LineMark(x: .value("Date", point.date), y: .value("Median", point.p50), series: .value("Series", "Median"))
                    .foregroundStyle(Palette.accent)
                    .lineStyle(StrokeStyle(lineWidth: Metrics.lineWidth, lineCap: .round, lineJoin: .round))
                    .interpolationMethod(.monotone)
            }
            if let last = fan.last {
                PointMark(x: .value("Date", last.date), y: .value("Median", last.p50))
                    .foregroundStyle(Palette.accent)
                    .symbolSize(30)
                    .annotation(position: .trailing, alignment: .center, spacing: 4) {
                        Text("median")
                            .font(.caption2)
                            .foregroundStyle(Palette.secondaryInk)
                    }
            }

            ForEach(actual) { point in
                LineMark(x: .value("Date", point.date), y: .value("Actual", point.value), series: .value("Series", "Actual"))
                    .foregroundStyle(Palette.ink)
                    .lineStyle(StrokeStyle(lineWidth: Metrics.lineWidth, lineCap: .round, lineJoin: .round))
            }

            ForEach(markers) { marker in
                RuleMark(x: .value("Date", marker.date))
                    .foregroundStyle(Palette.axis)
                    .lineStyle(StrokeStyle(lineWidth: 1, dash: [2, 3]))
                    .annotation(position: .top, alignment: .leading, spacing: 2) {
                        Label(marker.label, systemImage: marker.systemImage ?? "arrowtriangle.up.fill")
                            .labelStyle(.titleOnly)
                            .font(.caption2)
                            .foregroundStyle(Palette.secondaryInk)
                    }
            }

            if let selected = selectedPoint {
                RuleMark(x: .value("Date", selected.date))
                    .foregroundStyle(Palette.axis)
                    .lineStyle(StrokeStyle(lineWidth: 1))
                    .annotation(position: .top, spacing: 4,
                                overflowResolution: .init(x: .fit(to: .chart), y: .disabled)) {
                        callout(for: selected)
                    }
            }
        }
        .chartXSelection(value: $selectedDate)
        .chartYAxis { amountAxis(hidesAmounts: hidesAmounts) }
        .chartXAxis { dateAxis(spansYears: true, desiredCount: 5) }
        .chartLegend(.hidden)
    }

    private var selectedPoint: FanPoint? {
        guard let selectedDate else { return nil }
        return fan.min { abs($0.date.timeIntervalSince(selectedDate)) < abs($1.date.timeIntervalSince(selectedDate)) }
    }

    private func callout(for point: FanPoint) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(point.date, format: .dateTime.year())
                .font(.caption2)
                .foregroundStyle(Palette.secondaryInk)
            row("9 in 10 above", point.p10)
            row("Median", point.p50)
            row("1 in 10 above", point.p90)
        }
        .padding(Metrics.s)
        .background(Palette.card, in: RoundedRectangle(cornerRadius: 8, style: .continuous))
        .overlay { RoundedRectangle(cornerRadius: 8, style: .continuous).strokeBorder(Palette.border) }
    }

    private func row(_ label: String, _ value: Double) -> some View {
        HStack(spacing: Metrics.s) {
            Text(label).font(.caption2).foregroundStyle(Palette.secondaryInk)
            Spacer(minLength: Metrics.s)
            AmountText(Decimal(Int(value.rounded())), currency: currency).font(.caption2.weight(.semibold))
        }
        .frame(width: 180)
    }

    private var summary: ChartSummary {
        let resolved = currency ?? baseCurrency
        let points = fan.map { (String(Calendar.current.component(.year, from: $0.date)), $0.p50) }
        var text = "Projected portfolio: the median, with a band from the 10th to the 90th percentile."
        if let last = fan.last, !hidesAmounts {
            text += " At the end, the median is \(AmountFormat.amount(Decimal(Int(last.p50.rounded())), currency: resolved)); "
                + "in 9 of 10 simulated futures it's above "
                + "\(AmountFormat.amount(Decimal(Int(last.p10.rounded())), currency: resolved))."
        }
        return ChartSummary(
            title: "Your money over time", summary: text, xTitle: "Year", yTitle: "Portfolio",
            series: [ChartSummary.Series(name: "Median", points: points)],
            describeValue: ChartStyle.spokenAmount(currency: resolved))
    }
}

#Preview("Fan chart") {
    PreviewResultsView { results in
        Card("Your money over time") {
            FanChart(fan: results.portfolio, actual: PreviewLibrary.valuator.series(.planAssets,
                     through: PreviewLibrary.latestCheckIn).chartPoints, markers: results.markers)
        }
    }
}
