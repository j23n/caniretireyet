import Charts
import Model
import SwiftUI
import Tracker

/// Net worth over time (UI.md, "History chart").
///
/// - By default a single line in ink with a light fill. With `stacked`
///   series (e.g. by asset class) it draws stacked areas instead, debts
///   below the zero line, with a legend.
/// - `projection` continues the chart into the plan's future: a dashed
///   median with the 10–90% band. `markers` label retirement, pension
///   starts and the like on the time axis.
/// - Drag across it to read any date: a vertical rule with a callout
///   showing the date, the total and, when stacked, the breakdown.
///
///     NetWorthChart(history: valuator.series(through: date).chartPoints)
///     NetWorthChart(history: points, stacked: stacked.chartSeries, projection: fan, markers: markers)
struct NetWorthChart: View {
    var history: [ChartPoint]
    var stacked: [ChartSeries] = []
    var projection: [FanPoint] = []
    var markers: [ChartMarker] = []
    /// The currency of the values; `nil` for the base currency.
    var currency: CurrencyCode?
    var height: CGFloat = 220

    @State private var selectedDate: Date?
    @Environment(\.hidesAmounts) private var hidesAmounts
    @Environment(\.baseCurrency) private var baseCurrency

    var body: some View {
        if history.isEmpty && projection.isEmpty {
            ChartPlaceholder(text: "Your net worth appears here after the first check-in.", height: height)
        } else {
            chart
                .frame(height: height)
                .accessibilityChartDescriptor(summary)
        }
    }

    private var chart: some View {
        Chart {
            if stacked.isEmpty {
                ForEach(history) { point in
                    AreaMark(x: .value("Date", point.date), y: .value("Net worth", point.value),
                             series: .value("Series", "History fill"))
                        .foregroundStyle(Palette.ink.opacity(0.08))
                        .interpolationMethod(.monotone)
                    LineMark(x: .value("Date", point.date), y: .value("Net worth", point.value),
                             series: .value("Series", "History"))
                        .foregroundStyle(Palette.ink)
                        .lineStyle(StrokeStyle(lineWidth: Metrics.lineWidth, lineCap: .round, lineJoin: .round))
                        .interpolationMethod(.monotone)
                }
            } else {
                ForEach(stacked) { series in
                    ForEach(series.points) { point in
                        AreaMark(x: .value("Date", point.date), y: .value("Value", point.value), stacking: .standard)
                            .foregroundStyle(by: .value("Group", series.name))
                            .interpolationMethod(.monotone)
                    }
                }
            }

            ForEach(projection) { point in
                AreaMark(x: .value("Date", point.date), yStart: .value("10th percentile", point.p10),
                         yEnd: .value("90th percentile", point.p90), series: .value("Series", "Projection band"))
                    .foregroundStyle(Palette.accent.opacity(0.15))
                    .interpolationMethod(.monotone)
                LineMark(x: .value("Date", point.date), y: .value("Median", point.p50),
                         series: .value("Series", "Projection median"))
                    .foregroundStyle(Palette.accent)
                    .lineStyle(StrokeStyle(lineWidth: Metrics.lineWidth, lineCap: .round, dash: [5, 4]))
                    .interpolationMethod(.monotone)
            }

            ForEach(markers) { marker in
                RuleMark(x: .value("Date", marker.date))
                    .foregroundStyle(Palette.axis)
                    .lineStyle(StrokeStyle(lineWidth: 1, dash: [2, 3]))
                    .annotation(position: .top, alignment: .leading, spacing: 2) {
                        Text(marker.label)
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
                PointMark(x: .value("Date", selected.date), y: .value("Net worth", selected.value))
                    .foregroundStyle(Palette.ink)
                    .symbolSize(60)
            }
        }
        .chartForegroundStyleScale(domain: stacked.map(\.name), range: stacked.map { Palette.color(for: $0.color) })
        .chartLegend(position: .bottom, alignment: .leading)
        .chartXSelection(value: $selectedDate)
        .chartYAxis { amountAxis(hidesAmounts: hidesAmounts) }
        .chartXAxis { dateAxis(spansYears: (history + projection.map { ChartPoint(date: $0.date, value: $0.p50) }).spansYears) }
    }

    /// The history point nearest to the selected date.
    private var selectedPoint: ChartPoint? {
        guard let selectedDate else { return nil }
        return history.nearest(to: selectedDate)
    }

    private func callout(for point: ChartPoint) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(point.date, format: .dateTime.day().month(.abbreviated).year())
                .font(.caption2)
                .foregroundStyle(Palette.secondaryInk)
            AmountText(Decimal(Int(point.value.rounded())), currency: currency)
                .font(.caption.weight(.semibold))
            ForEach(stacked) { series in
                if let value = series.points.first(where: { $0.date == point.date })?.value, value != 0 {
                    HStack(spacing: 4) {
                        Circle().fill(Palette.color(for: series.color)).frame(width: 6, height: 6)
                        Text(series.name).font(.caption2).foregroundStyle(Palette.secondaryInk)
                        Spacer(minLength: 4)
                        AmountText(Decimal(Int(value.rounded())), currency: currency).font(.caption2)
                    }
                }
            }
        }
        .padding(Metrics.s)
        .frame(maxWidth: 200, alignment: .leading)
        .background(Palette.card, in: RoundedRectangle(cornerRadius: 8, style: .continuous))
        .overlay { RoundedRectangle(cornerRadius: 8, style: .continuous).strokeBorder(Palette.border) }
    }

    private var summary: ChartSummary {
        let resolved = currency ?? baseCurrency
        let points = history.map { (AmountFormat.mediumDate(CalendarDate($0.date, in: .current)), $0.value) }
        var text = "Net worth over \(history.count) dates"
        if let first = history.first, let last = history.last {
            text += hidesAmounts ? "." : ", from \(AmountFormat.amount(Decimal(Int(first.value.rounded())), currency: resolved)) "
                + "to \(AmountFormat.amount(Decimal(Int(last.value.rounded())), currency: resolved))."
        }
        if let end = projection.last {
            text += hidesAmounts ? " Projected ahead." : " Projected median at the end: "
                + "\(AmountFormat.amount(Decimal(Int(end.p50.rounded())), currency: resolved))."
        }
        return ChartSummary(
            title: "Net worth", summary: text, xTitle: "Date", yTitle: "Net worth",
            series: [ChartSummary.Series(name: "Net worth", points: points)],
            describeValue: ChartStyle.spokenAmount(currency: resolved))
    }
}

/// What a chart shows when it has no data: one clear sentence.
struct ChartPlaceholder: View {
    var text: String
    var height: CGFloat = 160

    var body: some View {
        Text(text)
            .font(.callout)
            .foregroundStyle(Palette.secondaryInk)
            .multilineTextAlignment(.center)
            .frame(maxWidth: .infinity, minHeight: height)
            .background(Palette.page.opacity(0.5), in: RoundedRectangle(cornerRadius: 12, style: .continuous))
    }
}

#Preview("Net worth") {
    let valuator = PreviewLibrary.valuator
    let end = PreviewLibrary.latestCheckIn
    ScrollView {
        VStack(spacing: Metrics.l) {
            Card("Net worth") {
                NetWorthChart(history: valuator.series(through: end).chartPoints)
            }
            Card("By asset class") {
                NetWorthChart(history: valuator.series(through: end).chartPoints,
                              stacked: valuator.breakdownSeries(through: end).chartSeries)
            }
            Card("With the future") {
                NetWorthChart(
                    history: valuator.series(through: end).chartPoints,
                    projection: [FanPoint(date: end.dateValue, p10: 190_000, p25: 190_000, p50: 190_000, p75: 190_000,
                                          p90: 190_000),
                                 FanPoint(date: end.adding(years: 5).dateValue, p10: 260_000, p25: 300_000, p50: 330_000,
                                          p75: 360_000, p90: 420_000)],
                    markers: [ChartMarker(date: end.adding(years: 3).dateValue, label: "New car")])
            }
            Card("Empty") {
                NetWorthChart(history: [])
            }
        }
        .padding()
    }
    .background(Palette.page)
}
