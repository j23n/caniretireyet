import Charts
import Model
import SwiftUI
import Tracker

/// Net worth over time (UI.md, "History chart"); the Overview always
/// passes it stacked by asset class.
///
/// - With `stacked` series (e.g. by asset class) it draws stacked areas,
///   debts below the zero line, with a legend in its own row above: each a
///   wash of its colour with a 2-point line in its line step along its
///   outer edge, and a 2-point surface gap between neighbours
///   (``StackedAreaData``), like the retirement income chart. Where a
///   total is partial (a price or exchange rate missing: `isComplete ==
///   false`) the lines are dashed, and the callout says so.
/// - Without them (or when every one is empty), a single line in ink with
///   a light fill, dashed and grey where a total is partial.
/// - The value axis always includes zero, with distinct round ticks
///   (``AmountScale``), even for flat or near-zero data. While amounts are
///   hidden it reads in multiples of today's value (`1×`, `2×`): the last
///   complete `history` total.
/// - `projection` continues the chart into the plan's future: a dashed
///   median, a darker 25–75% band and a lighter 10–90% band. The value axis
///   fits the history, the median and the 25–75% band; the 10–90% band may
///   run off the top, and the legend says so (``ProjectionScale``). Stacked,
///   the legend has two rows: the groups, then the projection's key. The
///   median starts from the last `history` total, so pass the totals of
///   what the projection covers.
/// - `markers` label retirement, pension starts and the like above the
///   data, staggered in up to two rows so they never collide; a marker
///   without room shows its icon, with its label in the callout
///   (``MarkerLabelLayout``).
/// - Time ticks fit the chart's width (``TimeTicks``).
/// - Drag across it to read any date: a vertical rule with a callout
///   showing the date, the total and, when stacked, the breakdown; over
///   the projection, its median and bands. The callout stays inside the chart.
///
///     NetWorthChart(history: valuator.series(through: date).chartPoints)
///     NetWorthChart(history: history.points, stacked: history.stacked, projection: history.projection,
///                   markers: history.markers)   // an OverviewHistory
struct NetWorthChart: View {
    var history: [ChartPoint]
    var stacked: [ChartSeries] = []
    var projection: [FanPoint] = []
    var markers: [ChartMarker] = []
    /// What the history is, for VoiceOver: "Net worth", or "Plan assets".
    var title = "Net worth"

    @State private var selectedDate: Date?
    @State private var width: CGFloat = ChartStyle.defaultWidth
    @Environment(\.hidesAmounts) private var hidesAmounts
    @Environment(\.baseCurrency) private var baseCurrency
    @Environment(\.chartSurface) private var surface

    private static let height: CGFloat = 220

    var body: some View {
        if history.isEmpty && projection.isEmpty {
            ChartPlaceholder(text: "Your net worth appears here after the first check-in.", height: Self.height)
        } else {
            let layout = self.layout
            VStack(alignment: .leading, spacing: Metrics.s) {
                legend(layout)
                chart(layout, stack: stacked.isEmpty ? nil : StackedAreaData(series: stacked))
                    .frame(height: Self.height)
                    .measuringWidth($width)
                    .accessibilityChartDescriptor(summary)
            }
        }
    }

    /// The groups' washes, and the projection's key under them: stacked,
    /// the groups stand for the past, so there's no "Actual" line.
    @ViewBuilder
    private func legend(_ layout: ProjectionLayout) -> some View {
        if !projection.isEmpty {
            VStack(alignment: .leading, spacing: Metrics.xs) {
                if !stacked.isEmpty {
                    groupLegend
                }
                ProjectionLegend(showsActual: !history.isEmpty && stacked.isEmpty, dashedMedian: true,
                                 clipsBand: layout.clipsBand)
            }
        } else if !stacked.isEmpty {
            groupLegend
        }
    }

    private var groupLegend: some View {
        ChartLegendRow(items: stacked.map { ChartLegendItem(name: $0.name, swatch: .wash($0.color)) })
    }

    /// Everything placed for the chart's width and height: the value axis
    /// fits the history and the stacked areas, and the projection's median
    /// and 25–75% band.
    private var layout: ProjectionLayout {
        let dates = history.map(\.date) + projection.map(\.date) + stacked.flatMap { $0.points.map(\.date) }
        return ProjectionLayout(dates: dates, values: history.map(\.value) + stacked.stackedExtents, fan: projection,
                                markers: markers, width: Double(width), height: Double(Self.height))
    }

    /// Today's value, the 1× of the axis while amounts are hidden.
    private var relativeBase: Double? {
        history.last(where: \.isComplete)?.value ?? projection.first?.p50
    }

    /// Solid for complete values; dashed where a price or rate is missing,
    /// so a partial total doesn't look like a fall.
    private func lineStyle(complete: Bool) -> StrokeStyle {
        complete
            ? StrokeStyle(lineWidth: Metrics.lineWidth, lineCap: .round, lineJoin: .round)
            : StrokeStyle(lineWidth: Metrics.lineWidth, lineCap: .round, lineJoin: .round, dash: [3, 4])
    }

    /// - Parameter stack: the stacked areas; `nil` without `stacked` series.
    private func chart(_ layout: ProjectionLayout, stack: StackedAreaData?) -> some View {
        Chart {
            if let stack {
                stackedAreas(stack)
            } else {
                ForEach(history) { point in
                    AreaMark(x: .value("Date", point.date), y: .value("Net worth", point.value),
                             series: .value("Series", "History fill"))
                        .foregroundStyle(Palette.ink.opacity(0.08))
                        .interpolationMethod(.monotone)
                        .spokenValueHidden(hidesAmounts)
                }
                ForEach(history.segments) { segment in
                    ForEach(segment.points) { point in
                        LineMark(x: .value("Date", point.date), y: .value("Net worth", point.value),
                                 series: .value("Series", "History \(segment.id)"))
                            .foregroundStyle(segment.isComplete ? Palette.ink : Palette.secondaryInk)
                            .lineStyle(lineStyle(complete: segment.isComplete))
                            .interpolationMethod(.monotone)
                            .spokenValueHidden(hidesAmounts)
                    }
                }
            }

            ForEach(layout.fan) { point in
                AreaMark(x: .value("Date", point.date), yStart: .value("10th percentile", point.p10),
                         yEnd: .value("90th percentile", point.p90), series: .value("Series", "Projection 10–90"))
                    .foregroundStyle(Palette.accent.opacity(ProjectionLegend.outerBand))
                    .interpolationMethod(.monotone)
                    .spokenValueHidden(hidesAmounts)
                AreaMark(x: .value("Date", point.date), yStart: .value("25th percentile", point.p25),
                         yEnd: .value("75th percentile", point.p75), series: .value("Series", "Projection 25–75"))
                    .foregroundStyle(Palette.accent.opacity(ProjectionLegend.innerBand))
                    .interpolationMethod(.monotone)
                    .spokenValueHidden(hidesAmounts)
                LineMark(x: .value("Date", point.date), y: .value("Median", point.p50),
                         series: .value("Series", "Projection median"))
                    .foregroundStyle(Palette.accent)
                    .lineStyle(StrokeStyle(lineWidth: Metrics.lineWidth, lineCap: .round, dash: [5, 4]))
                    .interpolationMethod(.monotone)
                    .spokenValueHidden(hidesAmounts)
            }

            markerRules(layout.markers, scale: layout.scale, hidesAmounts: hidesAmounts)

            if let selected = selection(layout) {
                // The callout stays inside the chart, never over what's above it.
                RuleMark(x: .value("Date", selected.date))
                    .foregroundStyle(Palette.secondaryInk)
                    .lineStyle(StrokeStyle(lineWidth: 1))
                    .annotation(position: .top, spacing: 4,
                                overflowResolution: .init(x: .fit(to: .chart), y: .fit(to: .chart))) {
                        callout(for: selected, layout: layout)
                    }
                PointMark(x: .value("Date", selected.date), y: .value("Net worth", selected.value))
                    .foregroundStyle(selected.isProjection ? Palette.accent : Palette.ink)
                    .symbolSize(60)
                    .spokenValueHidden(hidesAmounts)
            }
        }
        .chartLegend(.hidden)
        .chartXSelection(value: $selectedDate)
        .chartXScale(domain: layout.domain)
        .chartYScale(domain: layout.scale.domain)
        .chartYAxis { amountAxis(hidesAmounts: hidesAmounts, scale: layout.scale, relativeTo: relativeBase) }
        .chartXAxis { dateAxis(layout.ticks) }
    }

    /// Stacked areas (``StackedAreaData``): every band's wash, then the
    /// gaps in the surface the chart sits on (`\.chartSurface`), then the
    /// lines on top, so no wash or gap covers a line. Lines are dashed
    /// where the totals are partial.
    @ChartContentBuilder
    private func stackedAreas(_ stack: StackedAreaData) -> some ChartContent {
        ForEach(stack.series) { series in
            ForEach(stack.bands(of: series.id)) { point in
                AreaMark(x: .value("Date", point.date), yStart: .value("From", point.low),
                         yEnd: .value("To", point.high), series: .value("Group", series.id))
                    .foregroundStyle(Palette.color(for: series.color).opacity(StackedAreaData.fillOpacity))
                    .interpolationMethod(.linear)
                    .spokenValueHidden(hidesAmounts)
            }
        }
        ForEach(stack.edges) { point in
            LineMark(x: .value("Date", point.date), y: .value("Edge", point.y),
                     series: .value("Gap", "Gap \(point.line)"))
                .foregroundStyle(surface)
                .lineStyle(StrokeStyle(lineWidth: StackedAreaData.gapWidth, lineJoin: .round))
                .offset(x: 0, y: point.isBelowZero ? StackedAreaData.gapOffset : -StackedAreaData.gapOffset)
                .interpolationMethod(.linear)
                .spokenValueHidden(hidesAmounts)
        }
        ForEach(stack.zeroGap) { point in
            LineMark(x: .value("Date", point.date), y: .value("Zero", 0.0), series: .value("Gap", point.line))
                .foregroundStyle(surface)
                .lineStyle(StrokeStyle(lineWidth: StackedAreaData.gapWidth))
        }
        ForEach(stack.series) { series in
            ForEach(stack.edges(of: series.id)) { point in
                LineMark(x: .value("Date", point.date), y: .value("Edge", point.y),
                         series: .value("Edge", "Edge \(point.line)"))
                    .foregroundStyle(Palette.stroke(for: series.color))
                    .lineStyle(lineStyle(complete: point.isComplete))
                    .interpolationMethod(.linear)
                    .spokenValueHidden(hidesAmounts)
            }
        }
    }

    // MARK: Reading a date

    /// What the finger is on: a history point, or the projection beyond it.
    private struct Selection {
        var date: Date
        var value: Double
        var point: ChartPoint?
        var fan: FanPoint?

        var isProjection: Bool { fan != nil }
    }

    private func selection(_ layout: ProjectionLayout) -> Selection? {
        guard let selectedDate else { return nil }
        let lastHistory = history.last?.date ?? .distantPast
        if selectedDate > lastHistory || history.isEmpty,
           let fan = layout.fan.min(by: {
               abs($0.date.timeIntervalSince(selectedDate)) < abs($1.date.timeIntervalSince(selectedDate))
           }),
           let original = projection.first(where: { $0.date == fan.date }) {
            return Selection(date: fan.date, value: fan.p50, point: nil, fan: original)
        }
        guard let point = history.nearest(to: selectedDate) else { return nil }
        return Selection(date: point.date, value: point.value, point: point, fan: nil)
    }

    private func callout(for selection: Selection, layout: ProjectionLayout) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            if let fan = selection.fan {
                Text(fan.date, format: .dateTime.month(.abbreviated).year())
                    .font(.caption2)
                    .foregroundStyle(Palette.secondaryInk)
                calloutRow("Median") {
                    AmountText(Decimal(wholeNumber: fan.p50))
                }
                calloutRow("25–75%") { range(fan.p25, fan.p75) }
                calloutRow("10–90%") { range(fan.p10, fan.p90) }
            } else if let point = selection.point {
                Text(point.date, format: .dateTime.day().month(.abbreviated).year())
                    .font(.caption2)
                    .foregroundStyle(Palette.secondaryInk)
                AmountText(Decimal(wholeNumber: point.value))
                    .font(.caption.weight(.semibold))
                if !point.isComplete {
                    Text("Partial: some values are missing")
                        .font(.caption2)
                        .foregroundStyle(Palette.secondaryInk)
                }
                ForEach(stacked) { series in
                    if let value = series.points.first(where: { $0.date == point.date })?.value, value != 0 {
                        HStack(spacing: 4) {
                            Circle().fill(Palette.stroke(for: series.color)).frame(width: 6, height: 6)
                            Text(series.name).font(.caption2).foregroundStyle(Palette.secondaryInk)
                            Spacer(minLength: 4)
                            AmountText(Decimal(wholeNumber: value)).font(.caption2)
                        }
                    }
                }
            }
            ForEach(layout.markers.iconOnly(near: selection.date)) { marker in
                Label(marker.label, systemImage: marker.symbol)
                    .font(.caption2)
                    .foregroundStyle(Palette.secondaryInk)
            }
        }
        .padding(Metrics.s)
        .frame(maxWidth: 210, alignment: .leading)
        .calloutBackground()
    }

    private func calloutRow<Value: View>(_ title: String, @ViewBuilder value: () -> Value) -> some View {
        HStack(spacing: Metrics.s) {
            Text(title).foregroundStyle(Palette.secondaryInk)
            Spacer(minLength: Metrics.s)
            value()
        }
        .font(.caption2)
    }

    private func range(_ low: Double, _ high: Double) -> some View {
        HStack(spacing: 2) {
            AmountText(Decimal(wholeNumber: low))
            Text(verbatim: "–")
            AmountText(Decimal(wholeNumber: high))
        }
    }

    private var summary: ChartSummary {
        let currency = baseCurrency
        func spoken(_ points: [ChartPoint]) -> [(String, Double)] {
            points.map { (AmountFormat.mediumDate(CalendarDate($0.date, in: .current)), $0.value) }
        }
        var text = "\(title) over \(history.count) dates"
        if let first = history.first, let last = history.last {
            text += hidesAmounts ? "." : ", from \(AmountFormat.amount(Decimal(wholeNumber: first.value), currency: currency)) "
                + "to \(AmountFormat.amount(Decimal(wholeNumber: last.value), currency: currency))."
        }
        if !stacked.isEmpty {
            text += " Stacked: \(Wording.list(stacked.map(\.name)))."
        }
        let partial = history.filter { !$0.isComplete }.count
        if partial > 0 {
            text += " \(partial == 1 ? "1 date is" : "\(partial) dates are") partial: some values are missing."
        }
        if let end = projection.last {
            text += hidesAmounts ? " Projected ahead." : " Projected median at the end: "
                + "\(AmountFormat.amount(Decimal(wholeNumber: end.p50), currency: currency))."
        }
        if !markers.isEmpty {
            text += " Marked: \(markers.map(\.label).joined(separator: ", "))."
        }
        let groups = stacked.map { ChartSummary.Series(name: $0.name, points: spoken($0.points)) }
        return ChartSummary(
            title: title, summary: text, xTitle: "Date", yTitle: title,
            series: [ChartSummary.Series(name: title, points: spoken(history))] + groups,
            describeValue: ChartStyle.spokenAmount(currency: currency, hidden: hidesAmounts))
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
    let history = valuator.series(through: end).chartPoints
    // Made-up: a projection whose 10–90% band runs off the top, and markers close together.
    let fan = (0...30).map { year in
        let median = 190_000 * pow(1.03, Double(year))
        let spread = 0.12 * Double(year).squareRoot()
        return FanPoint(date: end.adding(years: year).dateValue, p10: median * exp(-1.28 * spread),
                        p25: median * exp(-0.67 * spread), p50: median, p75: median * exp(0.67 * spread),
                        p90: median * exp(1.28 * spread))
    }
    let markers = [
        ChartMarker(date: end.adding(years: 12).dateValue, label: "Retire at 50", systemImage: "figure.walk",
                    kind: .retirement),
        ChartMarker(date: end.adding(years: 19).dateValue, label: "Pension fund 57", systemImage: "lock.open"),
        ChartMarker(date: end.adding(years: 21).dateValue, label: "State pension 67", systemImage: "building.columns"),
        ChartMarker(date: end.adding(years: 22).dateValue, label: "BMW 60", systemImage: "building.columns"),
    ]
    // As the Overview has them: net worth, and plan assets with the future.
    let netWorth = OverviewHistory(valuator: valuator, through: end, range: .all)
    let planAssets = OverviewHistory(valuator: valuator, through: end, range: .all, projection: fan, markers: markers)
    // Made-up: a dollar account's rate is missing for the first five months, so equity is partly left out.
    let months = (0..<12).map { end.adding(months: $0 - 11).dateValue }
    let partialCash = months.enumerated().map { month, date in
        ChartPoint(date: date, value: 60_000, isComplete: month >= 5)
    }
    let partialEquity = months.enumerated().map { month, date in
        ChartPoint(date: date, value: month < 5 ? 120_000 : 200_000, isComplete: month >= 5)
    }
    ScrollView {
        VStack(spacing: Metrics.l) {
            Card("Net worth") {
                NetWorthChart(history: history)
            }
            Card("By asset class") {
                NetWorthChart(history: netWorth.points, stacked: netWorth.stacked)
            }
            Card("Plan assets by asset class, with the future") {
                NetWorthChart(history: planAssets.points, stacked: planAssets.stacked,
                              projection: planAssets.projection, markers: planAssets.markers, title: "Plan assets")
            }
            Card("With the future, amounts hidden") {
                NetWorthChart(history: planAssets.points, stacked: planAssets.stacked,
                              projection: planAssets.projection, markers: planAssets.markers, title: "Plan assets")
                    .environment(\.hidesAmounts, true)
            }
            Card("By asset class, some values missing") {
                NetWorthChart(
                    history: zip(partialCash, partialEquity).map { cash, equity in
                        ChartPoint(date: cash.date, value: cash.value + equity.value, isComplete: cash.isComplete)
                    },
                    stacked: [
                        ChartSeries(id: "cash", name: "Cash", color: .assetClass(.cash), points: partialCash),
                        ChartSeries(id: "equity", name: "Equity", color: .assetClass(.equity), points: partialEquity),
                    ])
            }
            Card("Some values missing") {
                // Made-up: an account's rate is missing for the first five months.
                NetWorthChart(history: (0..<12).map { month in
                    ChartPoint(date: end.adding(months: month - 11).dateValue, value: month < 5 ? 180_000 : 260_000,
                               isComplete: month >= 5)
                })
            }
            Card("Flat at zero") {
                NetWorthChart(history: (0..<12).map { month in
                    ChartPoint(date: end.adding(months: month - 11).dateValue, value: 0)
                })
            }
            Card("Empty") {
                NetWorthChart(history: [])
            }
        }
        .padding()
    }
    .background(Palette.page)
}
