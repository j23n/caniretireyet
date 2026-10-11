import Charts
import Model
import SwiftUI
import Tracker

/// Trends' *Where your money came from* (UI.md, "Trends"): plan assets at
/// each month end or year end, stacked into what you started with, what you
/// put in and what markets added, with plan assets as an ink line on top.
/// When markets have taken away more than they added, the line runs below
/// the top of what you put in, and the gap is shaded orange. While amounts
/// are hidden the value axis reads in multiples of today's plan assets.
/// Drag across it to read a month or year.
struct PlanMoneySourcesChart: View {
    let sources: PlanMoneySources

    @State private var selectedDate: Date?
    @State private var width: CGFloat = ChartStyle.defaultWidth
    @Environment(\.redactionReasons) private var redactionReasons

    static let height: CGFloat = 200

    /// Started with: grey; put in: the accent; markets added: aqua; what
    /// markets took: orange.
    static let startedColor = ChartColor.neutral
    static let putInColor = ChartColor.accent
    static let marketsColor = ChartColor.series(2)
    static let lossColor = ChartColor.series(1)

    private var hidesAmounts: Bool { redactionReasons.hidesAmounts }

    /// One point's bands, from zero up.
    private struct Band: Identifiable {
        var point: MoneySourcesPoint
        var date: Date
        /// Started with.
        var started: Double
        /// Started with and put in.
        var putIn: Double
        /// Plan assets.
        var total: Double

        var id: Date { date }
    }

    private var bands: [Band] {
        sources.points.map { point in
            let started = point.startedWith.doubleValue
            return Band(point: point, date: point.date.dateValue, started: started,
                        putIn: started + point.putIn.doubleValue, total: point.total.doubleValue)
        }
    }

    var body: some View {
        let bands = self.bands
        let scale = AmountScale(values: bands.flatMap { [$0.started, $0.putIn, $0.total] })
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

    private func chart(_ bands: [Band], scale: AmountScale, domain: ClosedRange<Date>) -> some View {
        Chart {
            ForEach(bands) { band in
                AreaMark(x: .value("Date", band.date), yStart: .value("From", 0.0),
                         yEnd: .value("Started with", band.started), series: .value("Part", "Started with"))
                    .foregroundStyle(Palette.color(for: Self.startedColor).opacity(StackedAreaData.fillOpacity))
                    .spokenValueHidden(hidesAmounts)
                AreaMark(x: .value("Date", band.date), yStart: .value("From", band.started),
                         yEnd: .value("Put in", band.putIn), series: .value("Part", "Put in"))
                    .foregroundStyle(Palette.color(for: Self.putInColor).opacity(StackedAreaData.fillOpacity))
                    .spokenValueHidden(hidesAmounts)
                AreaMark(x: .value("Date", band.date), yStart: .value("From", band.putIn),
                         yEnd: .value("Markets added", max(band.total, band.putIn)),
                         series: .value("Part", "Markets added"))
                    .foregroundStyle(Palette.color(for: Self.marketsColor).opacity(StackedAreaData.fillOpacity))
                    .spokenValueHidden(hidesAmounts)
                AreaMark(x: .value("Date", band.date), yStart: .value("From", min(band.total, band.putIn)),
                         yEnd: .value("Markets took", band.putIn), series: .value("Part", "Markets took"))
                    .foregroundStyle(Palette.color(for: Self.lossColor).opacity(0.45))
                    .spokenValueHidden(hidesAmounts)
            }
            ForEach(bands) { band in
                LineMark(x: .value("Date", band.date), y: .value("Put in", band.putIn),
                         series: .value("Line", "Put in"))
                    .foregroundStyle(Palette.stroke(for: Self.putInColor))
                    .lineStyle(StrokeStyle(lineWidth: 1, lineJoin: .round))
                    .spokenValueHidden(hidesAmounts)
                LineMark(x: .value("Date", band.date), y: .value("Plan assets", band.total),
                         series: .value("Line", "Plan assets"))
                    .foregroundStyle(Palette.ink)
                    .lineStyle(StrokeStyle(lineWidth: Metrics.lineWidth, lineCap: .round, lineJoin: .round))
                    .spokenValueHidden(hidesAmounts)
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
            ChartCalloutRow("You put in", swatch: Palette.stroke(for: Self.putInColor),
                            amount: band.point.putIn.doubleValue)
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
                + "started with, what you put in and what markets added.",
            xTitle: "Date", yTitle: "Plan assets",
            series: [
                ChartSummary.Series(name: "Plan assets", points: spoken(\.total)),
                ChartSummary.Series(name: "You started with", points: spoken(\.startedWith)),
                ChartSummary.Series(name: "You put in", points: spoken(\.putIn)),
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
            ChartLegendItem(name: "You put in", swatch: .wash(PlanMoneySourcesChart.putInColor)),
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
