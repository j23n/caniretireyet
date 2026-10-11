import Charts
import Model
import SwiftUI
import Tracker

/// Trends' *Savings rate* (UI.md, "Trends"): a bar per month or year, the
/// savings rate over the values of that period, below the zero line when
/// more went out than came in. With months, a line through the rate over
/// the 12 months ending at each month, from the twelfth month recorded. A
/// dashed rule at the plan's own savings rate while working. The value axis
/// fits the line, the rule and the bars within ±100%
/// (``PlanMoneyInOut/rateAxisValues(planRate:)``); a bar beyond is drawn to
/// the axis's edge, and its callout reads the real rate. Rates stay with
/// the eye. The current month or year is drawn lighter ("so far"). Drag
/// across it to read a period (``PlanMoneyInOutCallout``).
struct PlanSavingsRateChart: View {
    let money: PlanMoneyInOut
    /// The plan's own savings rate while working; `nil` without a work
    /// phase in force.
    var planRate: Decimal?

    @State private var selectedDate: Date?
    @State private var width: CGFloat = ChartStyle.defaultWidth

    static let height: CGFloat = 180

    /// The bars: the accent.
    static let barColor = ChartColor.accent

    /// One period's bar and line point, in percentage points.
    private struct Bar: Identifiable {
        var period: MoneyInOutPeriod
        var start: Date
        var end: Date
        var middle: Date
        var rate: Double?
        var lastTwelveMonths: Double?
        var isSoFar: Bool

        var id: Date { start }
        /// Keeps the bar's area apart from the others'.
        var key: String { period.from.description }
        /// How high the bar is drawn: its rate, kept within the value
        /// axis's `domain`.
        func height(within domain: ClosedRange<Double>) -> Double {
            PlanMoneyInOut.clampedRate(rate ?? 0, to: domain)
        }
        /// How much of its colour the bar keeps.
        var opacity: Double { isSoFar ? PlanSavingsRateChart.soFarOpacity : 1 }
    }

    private var bars: [Bar] {
        money.periods.map { period in
            let span = money.timeSpan(of: period)
            return Bar(period: period, start: PlanMoneyInOut.date(0.15, across: span),
                       end: PlanMoneyInOut.date(0.85, across: span), middle: money.middle(of: period),
                       rate: period.rate.map { $0.doubleValue * 100 },
                       lastTwelveMonths: period.lastTwelveMonths?.rate.map { $0.doubleValue * 100 },
                       isSoFar: money.isSoFar(period))
        }
    }

    private var planPoints: Double? { planRate.map { $0.doubleValue * 100 } }

    var body: some View {
        let bars = self.bars
        let scale = AmountScale(values: money.rateAxisValues(planRate: planRate).map { $0 * 100 })
        let domain = money.domain ?? (Date.now...Date.now.addingTimeInterval(31 * 86_400))
        chart(bars, scale: scale, domain: domain)
            .frame(height: Self.height)
            .measuringWidth($width)
            .accessibilityChartDescriptor(summary(bars))
            .privacySensitiveInFeedback()
    }

    /// How much of its colour the "so far" bar keeps.
    private static let soFarOpacity = 0.45

    /// The period nearest the pointer or a finger.
    private var selectedPeriod: MoneyInOutPeriod? {
        guard let selectedDate else { return nil }
        return money.period(nearest: selectedDate)
    }

    private func chart(_ bars: [Bar], scale: AmountScale, domain: ClosedRange<Date>) -> some View {
        let ticks = TimeTicks(domain: domain, plotWidth: max(Double(width) - 48, 1))
        let rated: [Bar] = bars.filter { $0.rate != nil }
        let rolling: [Bar] = bars.filter { $0.lastTwelveMonths != nil }
        return Chart {
            rateBars(rated, within: scale.domain)
            zeroRule()
            lastTwelveMonthsLine(rolling)
            planRule()
            selectionRule(selectedPeriod)
        }
        .chartLegend(.hidden)
        .chartXSelection(value: $selectedDate)
        .chartXScale(domain: domain)
        .chartYScale(domain: scale.domain)
        .chartYAxis { Self.rateAxis(scale.ticks) }
        .chartXAxis { dateAxis(ticks) }
    }

    /// Each bar, an area from zero to its rate between its start and its
    /// end, drawn to the edge of the value axis's `domain` when its rate is
    /// beyond it; `key` keeps a bar's area apart from the others'.
    @ChartContentBuilder
    private func rateBars(_ bars: [Bar], within domain: ClosedRange<Double>) -> some ChartContent {
        ForEach(bars) { bar in
            AreaMark(x: .value("Date", bar.start), yStart: .value("From", 0.0),
                     yEnd: .value("Savings rate", bar.height(within: domain)), series: .value("Bar", bar.key))
                .foregroundStyle(Palette.color(for: Self.barColor).opacity(bar.opacity))
            AreaMark(x: .value("Date", bar.end), yStart: .value("From", 0.0),
                     yEnd: .value("Savings rate", bar.height(within: domain)), series: .value("Bar", bar.key))
                .foregroundStyle(Palette.color(for: Self.barColor).opacity(bar.opacity))
        }
    }

    @ChartContentBuilder
    private func zeroRule() -> some ChartContent {
        RuleMark(y: .value("Zero", 0.0))
            .foregroundStyle(Palette.axis)
            .lineStyle(StrokeStyle(lineWidth: 1))
    }

    /// The rate over the 12 months ending at each month.
    @ChartContentBuilder
    private func lastTwelveMonthsLine(_ bars: [Bar]) -> some ChartContent {
        ForEach(bars) { bar in
            LineMark(x: .value("Date", bar.middle), y: .value("Last 12 months", bar.lastTwelveMonths ?? 0.0),
                     series: .value("Line", "Last 12 months"))
                .foregroundStyle(Palette.ink)
                .lineStyle(StrokeStyle(lineWidth: Metrics.lineWidth, lineCap: .round, lineJoin: .round))
        }
    }

    /// The plan's own savings rate, dashed.
    @ChartContentBuilder
    private func planRule() -> some ChartContent {
        if let planPoints {
            RuleMark(y: .value("Your plan's", planPoints))
                .foregroundStyle(Palette.secondaryInk)
                .lineStyle(StrokeStyle(lineWidth: 1.5, dash: [4, 3]))
        }
    }

    /// The selected period's rule and its callout.
    @ChartContentBuilder
    private func selectionRule(_ period: MoneyInOutPeriod?) -> some ChartContent {
        if let period {
            RuleMark(x: .value("Date", money.middle(of: period)))
                .foregroundStyle(Palette.secondaryInk)
                .lineStyle(StrokeStyle(lineWidth: 1))
                .annotation(position: .top, spacing: 4,
                            overflowResolution: .init(x: .fit(to: .chart), y: .fit(to: .chart))) {
                    callout(for: period)
                }
        }
    }

    private func callout(for period: MoneyInOutPeriod) -> some View {
        PlanMoneyInOutCallout(money: money, period: period)
    }

    /// Faint gridlines at the scale's ticks, labelled as percentages ("30%").
    private static func rateAxis(_ ticks: [Double]) -> some AxisContent {
        AxisMarks(position: .leading, values: ticks) { value in
            AxisGridLine(stroke: StrokeStyle(lineWidth: 0.5))
                .foregroundStyle(Palette.gridline)
            AxisValueLabel {
                if let points = value.as(Double.self) {
                    Text(verbatim: AmountFormat.percent(points / 100, digits: 0))
                        .font(.caption2)
                        .monospacedDigit()
                        .foregroundStyle(Palette.mutedInk)
                }
            }
        }
    }

    private func summary(_ bars: [Bar]) -> ChartSummary {
        let unit = money.grain == .months ? "month" : "year"
        var series = [ChartSummary.Series(
            name: "Savings rate",
            points: bars.compactMap { bar in bar.rate.map { (AmountFormat.mediumDate(bar.period.through), $0) } })]
        let rolling = bars.compactMap { bar in
            bar.lastTwelveMonths.map { (AmountFormat.mediumDate(bar.period.through), $0) }
        }
        if !rolling.isEmpty { series.append(ChartSummary.Series(name: "The last 12 months", points: rolling)) }
        var text = "What you kept of what came in, each \(unit)."
        if let planRate {
            text += " Your plan's savings rate is \(AmountFormat.percent(planRate, digits: 0))."
        }
        return ChartSummary(title: "Savings rate", summary: text, xTitle: "Date", yTitle: "Savings rate",
                            series: series, describeValue: { AmountFormat.percent($0 / 100, digits: 0) })
    }
}

/// The key of *Savings rate*: the line over the last 12 months when it's
/// drawn, and the plan's rate ("Your plan's 28%") when there's one.
struct PlanSavingsRateLegend: View {
    let showsLastTwelveMonths: Bool
    var planRate: Decimal?

    var body: some View {
        var items = [ChartLegendItem(name: "Savings rate", swatch: .bar(PlanSavingsRateChart.barColor))]
        if showsLastTwelveMonths {
            items.append(ChartLegendItem(name: "The last 12 months", swatch: .line(.ink, dashed: false)))
        }
        if let planRate {
            items.append(ChartLegendItem(name: "Your plan's \(AmountFormat.percent(planRate, digits: 0))",
                                         swatch: .line(.taxes, dashed: true)))
        }
        return ChartLegendRow(items: items)
    }
}
