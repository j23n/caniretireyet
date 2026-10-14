import Charts
import Model
import SwiftUI
import Tracker

/// Trends' *Where your money came from* (UI.md, "Trends"): plan assets at
/// each month end or year end, stacked into what you started with, what you
/// saved and what markets added, with plan assets as an ink line on top.
/// When markets have taken away more than they added, the line runs below
/// the top of what you saved, and the gap is shaded orange. The current
/// month or year, not over yet, is drawn lighter ("so far"); a single point
/// is drawn as dots. While amounts are hidden the value axis reads in
/// multiples of today's plan assets. Drag across it to read a month or year.
struct PlanMoneySourcesChart: View {
    let sources: PlanMoneySources

    @State private var selectedDate: Date?
    @State private var width: CGFloat = ChartStyle.defaultWidth
    @Environment(\.redactionReasons) private var redactionReasons

    static let height: CGFloat = 200

    /// Started with: grey; saved: the accent; markets added: aqua; what
    /// markets took: orange.
    static let startedColor = ChartColor.neutral
    static let savedColor = ChartColor.accent
    static let marketsColor = ChartColor.series(2)
    static let lossColor = ChartColor.series(1)

    private var hidesAmounts: Bool { redactionReasons.hidesAmounts }

    /// One point's bands, from zero up.
    private struct Band: Identifiable {
        var point: MoneySourcesPoint
        var date: Date
        /// Started with.
        var started: Double
        /// Started with and saved.
        var saved: Double
        /// Plan assets.
        var total: Double

        var id: Date { date }
    }

    private var bands: [Band] {
        sources.points.map { point in
            let started = point.startedWith.doubleValue
            return Band(point: point, date: point.date.dateValue, started: started,
                        saved: started + point.saved.doubleValue, total: point.total.doubleValue)
        }
    }

    var body: some View {
        let bands = self.bands
        let scale = AmountScale(values: bands.flatMap { [$0.started, $0.saved, $0.total] })
        let domain = Self.domain(of: bands.map(\.date))
        chart(bands, scale: scale, domain: domain)
            .frame(height: Self.height)
            .measuringWidth($width)
            .accessibilityChartDescriptor(summary(bands))
            .privacySensitiveInFeedback()
    }

    /// From the first point to the last, at least a month wide.
    private static func domain(of dates: [Date]) -> ClosedRange<Date> {
        let first = dates.first ?? .now
        let last = max(dates.last ?? first, first.addingTimeInterval(31 * 86_400))
        return first...last
    }

    /// The bands drawn in full, and the stretch into the current month or
    /// year, drawn lighter: from the last whole one to the latest check-in.
    private struct Stretches {
        var whole: [Band]
        var soFar: [Band]
    }

    private func stretches(of bands: [Band]) -> Stretches {
        guard let last = bands.last, sources.isSoFar(last.point) else { return Stretches(whole: bands, soFar: []) }
        return Stretches(whole: Array(bands.dropLast()), soFar: Array(bands.suffix(2)))
    }

    /// How much of its colour the "so far" stretch keeps.
    private static let soFarOpacity = 0.45

    private func chart(_ bands: [Band], scale: AmountScale, domain: ClosedRange<Date>) -> some View {
        let stretches = self.stretches(of: bands)
        return Chart {
            areas(stretches.whole, stretch: "", opacity: 1)
            areas(stretches.soFar, stretch: " so far", opacity: Self.soFarOpacity)
            lines(stretches.whole, stretch: "", opacity: 1)
            lines(stretches.soFar, stretch: " so far", opacity: Self.soFarOpacity)
            // An area or a line needs two points: one alone is drawn as dots.
            if bands.count == 1, let band = bands.first {
                dots(band, opacity: sources.isSoFar(band.point) ? Self.soFarOpacity : 1)
            }
            if let selected = selection(in: bands) {
                RuleMark(x: .value("Date", selected.date))
                    .foregroundStyle(Palette.secondaryInk)
                    .lineStyle(StrokeStyle(lineWidth: 1))
                    .annotation(position: .top, spacing: 4,
                                overflowResolution: .init(x: .fit(to: .chart), y: .fit(to: .chart))) {
                        callout(for: selected)
                    }
                PointMark(x: .value("Date", selected.date), y: .value("Plan assets", selected.total))
                    .foregroundStyle(Palette.ink)
                    .symbolSize(60)
                    .spokenValueHidden(hidesAmounts)
            }
        }
        .chartLegend(.hidden)
        .chartXSelection(value: $selectedDate)
        .chartXScale(domain: domain)
        .chartYScale(domain: scale.domain)
        .chartYAxis { amountAxis(hidesAmounts: hidesAmounts, scale: scale, relativeTo: sources.relativeBase) }
        .chartXAxis { dateAxis(TimeTicks(domain: domain, plotWidth: max(Double(width) - 48, 1))) }
    }

    /// The three parts' washes, and the orange gap where markets took more
    /// than they added. `stretch` keeps a stretch's areas apart from the
    /// others'.
    @ChartContentBuilder
    private func areas(_ bands: [Band], stretch: String, opacity: Double) -> some ChartContent {
        ForEach(bands) { band in
            AreaMark(x: .value("Date", band.date), yStart: .value("From", 0.0),
                     yEnd: .value("Started with", band.started), series: .value("Part", "Started with" + stretch))
                .foregroundStyle(Palette.color(for: Self.startedColor)
                    .opacity(StackedAreaData.fillOpacity * opacity))
                .spokenValueHidden(hidesAmounts)
            AreaMark(x: .value("Date", band.date), yStart: .value("From", band.started),
                     yEnd: .value("Saved", band.saved), series: .value("Part", "Saved" + stretch))
                .foregroundStyle(Palette.color(for: Self.savedColor).opacity(StackedAreaData.fillOpacity * opacity))
                .spokenValueHidden(hidesAmounts)
            AreaMark(x: .value("Date", band.date), yStart: .value("From", band.saved),
                     yEnd: .value("Markets added", max(band.total, band.saved)),
                     series: .value("Part", "Markets added" + stretch))
                .foregroundStyle(Palette.color(for: Self.marketsColor)
                    .opacity(StackedAreaData.fillOpacity * opacity))
                .spokenValueHidden(hidesAmounts)
            AreaMark(x: .value("Date", band.date), yStart: .value("From", min(band.total, band.saved)),
                     yEnd: .value("Markets took", band.saved), series: .value("Part", "Markets took" + stretch))
                .foregroundStyle(Palette.color(for: Self.lossColor).opacity(0.45 * opacity))
                .spokenValueHidden(hidesAmounts)
        }
    }

    /// The line along the top of what you saved, and plan assets in ink.
    @ChartContentBuilder
    private func lines(_ bands: [Band], stretch: String, opacity: Double) -> some ChartContent {
        ForEach(bands) { band in
            LineMark(x: .value("Date", band.date), y: .value("Saved", band.saved),
                     series: .value("Line", "Saved" + stretch))
                .foregroundStyle(Palette.stroke(for: Self.savedColor).opacity(opacity))
                .lineStyle(StrokeStyle(lineWidth: 1, lineJoin: .round))
                .spokenValueHidden(hidesAmounts)
            LineMark(x: .value("Date", band.date), y: .value("Plan assets", band.total),
                     series: .value("Line", "Plan assets" + stretch))
                .foregroundStyle(Palette.ink.opacity(opacity))
                .lineStyle(StrokeStyle(lineWidth: Metrics.lineWidth, lineCap: .round, lineJoin: .round))
                .spokenValueHidden(hidesAmounts)
        }
    }

    /// A single point's parts: the top of what you started with and of what
    /// you saved, and plan assets in ink.
    @ChartContentBuilder
    private func dots(_ band: Band, opacity: Double) -> some ChartContent {
        PointMark(x: .value("Date", band.date), y: .value("Started with", band.started))
            .foregroundStyle(Palette.stroke(for: Self.startedColor).opacity(opacity))
            .symbolSize(30)
            .spokenValueHidden(hidesAmounts)
        PointMark(x: .value("Date", band.date), y: .value("Saved", band.saved))
            .foregroundStyle(Palette.stroke(for: Self.savedColor).opacity(opacity))
            .symbolSize(30)
            .spokenValueHidden(hidesAmounts)
        PointMark(x: .value("Date", band.date), y: .value("Plan assets", band.total))
            .foregroundStyle(Palette.ink.opacity(opacity))
            .symbolSize(40)
            .spokenValueHidden(hidesAmounts)
    }

    private func selection(in bands: [Band]) -> Band? {
        guard let selectedDate else { return nil }
        return bands.min { abs($0.date.timeIntervalSince(selectedDate)) < abs($1.date.timeIntervalSince(selectedDate)) }
    }

    /// "31 Mar 2026", "30 Sep 2026 · so far", plan assets, then each part.
    private func callout(for band: Band) -> some View {
        ChartCallout {
            ChartCalloutDate(band.date, detail: sources.isSoFar(band.point) ? "so far" : nil)
            ChartCalloutTotal(band.total)
            if !band.point.isPriced {
                Text("Not every price is known")
                    .font(.caption2)
                    .foregroundStyle(Palette.secondaryInk)
            }
            ChartCalloutRow("You started with", swatch: Palette.stroke(for: Self.startedColor),
                            amount: band.point.startedWith.doubleValue)
            ChartCalloutRow("You saved", swatch: Palette.stroke(for: Self.savedColor),
                            amount: band.point.saved.doubleValue)
            ChartCalloutRow(band.point.markets >= 0 ? "Markets added" : "Markets took",
                            swatch: Palette.stroke(for: band.point.markets >= 0 ? Self.marketsColor : Self.lossColor),
                            amount: abs(band.point.markets.doubleValue))
        }
    }

    private func summary(_ bands: [Band]) -> ChartSummary {
        func spoken(_ value: KeyPath<MoneySourcesPoint, Decimal>) -> [(String, Double)] {
            bands.map { (AmountFormat.mediumDate($0.point.date), $0.point[keyPath: value].doubleValue) }
        }
        return ChartSummary(
            title: "Where your money came from",
            summary: "Plan assets at each \(sources.grain == .months ? "month" : "year") end, split into what you "
                + "started with, what you saved and what markets added.",
            xTitle: "Date", yTitle: "Plan assets",
            series: [
                ChartSummary.Series(name: "Plan assets", points: spoken(\.total)),
                ChartSummary.Series(name: "You started with", points: spoken(\.startedWith)),
                ChartSummary.Series(name: "You saved", points: spoken(\.saved)),
                ChartSummary.Series(name: "Markets added", points: spoken(\.markets)),
            ],
            describeValue: ChartStyle.spokenAmount(currency: sources.currency, hidden: hidesAmounts))
    }
}

/// The key of *Where your money came from*: the parts' washes, and the
/// orange gap when markets ever took away more than they added.
struct PlanMoneySourcesLegend: View {
    let showsLoss: Bool

    var body: some View {
        var items = [
            ChartLegendItem(name: "You started with", swatch: .wash(PlanMoneySourcesChart.startedColor)),
            ChartLegendItem(name: "You saved", swatch: .wash(PlanMoneySourcesChart.savedColor)),
            ChartLegendItem(name: "Markets added", swatch: .wash(PlanMoneySourcesChart.marketsColor)),
        ]
        if showsLoss {
            items.append(ChartLegendItem(name: "Markets took", swatch: .wash(PlanMoneySourcesChart.lossColor)))
        }
        return ChartLegendRow(items: items)
    }
}

#Preview("Where your money came from") {
    let valuator = PreviewLibrary.valuator
    let end = PreviewLibrary.latestCheckIn
    let sources = PlanMoneySources(valuator.moneySources(.months, through: end), grain: .months, from: nil,
                                   checkIns: valuator.checkInDates(in: .planAssets, through: end).count)
    VStack(spacing: Metrics.l) {
        Card("Where your money came from") {
            PlanMoneySourcesLegend(showsLoss: sources.hasLoss)
            PlanMoneySourcesChart(sources: sources)
        }
        Card("Amounts hidden") {
            PlanMoneySourcesChart(sources: sources)
                .redacted(reason: .privacy)
        }
    }
    .padding()
    .background(Palette.page)
    .previewEnvironment()
}
