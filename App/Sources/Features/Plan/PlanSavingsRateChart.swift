import Charts
import Model
import SwiftUI
import Tracker

/// Trends' *Savings rate* (UI.md, "Trends"): a bar per month or year, the
/// savings rate over the values of that period, below the zero line when
/// more was spent than came in. With months, a line through the rate over
/// the 12 months ending at each month, from the twelfth month recorded,
/// broken where those 12 months have no rate
/// (``PlanMoneyInOut/lastTwelveMonthsRuns``). A period with money in and
/// out but no rate (nothing came in after tax) has no bar, but what it
/// spent counts in the line: a dot at the value axis's bottom edge marks
/// it, "No rate" in the legend (``PlanMoneyInOut/countedWithoutRate``),
/// and its callout says why. A dashed rule at the plan's own savings rate
/// while working. The value axis fits the rule, and the bars and the line
/// around what's typical for each period
/// (``PlanMoneyInOut/rateAxisValues(planRate:)``); a bar beyond is drawn
/// to the axis's edge with a gap, the line along the edge with triangles
/// (``ChartCut``), and the callout and VoiceOver read the real rate. Rates
/// stay with the eye. The current month or year is drawn lighter ("so
/// far"). Drag across it to read a period (``PlanSavingsRateCallout``).
struct PlanSavingsRateChart: View {
    let money: PlanMoneyInOut
    /// The plan's own savings rate while working; `nil` without a work
    /// phase in force.
    var planRate: Decimal?

    @State private var selectedDate: Date?
    @State private var width: CGFloat = ChartStyle.defaultWidth
    @Environment(\.locale) private var locale
    @Environment(\.chartSurface) private var surface

    static let height: CGFloat = 180

    /// The bars: the accent.
    static let barColor = ChartColor.accent
    /// A period without a bar, at the axis's bottom edge: spent's colour on
    /// *Money in and out*, since only spending was counted.
    static let withoutRateColor = PlanMoneyInOutChart.spentColor

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
            PlanMoneyInOut.clamped(rate ?? 0, to: domain)
        }
        /// How much of its colour the bar keeps.
        var opacity: Double { isSoFar ? PlanSavingsRateChart.soFarOpacity : 1 }
    }

    /// A point of the line over 12 months, in percentage points, in its run.
    private struct LinePoint: Identifiable {
        /// The run it's in, from 0: each run is a line of its own.
        var run: Int
        var middle: Date
        var rate: Double
        /// Whether it's a run of its own, which draws no line: a dot.
        var isAlone: Bool

        var id: Date { middle }
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

    private var linePoints: [LinePoint] {
        money.lastTwelveMonthsRuns.enumerated().flatMap { run, periods in
            periods.compactMap { period in
                period.lastTwelveMonths?.rate.map {
                    LinePoint(run: run, middle: money.middle(of: period), rate: $0.doubleValue * 100,
                              isAlone: periods.count == 1)
                }
            }
        }
    }

    private var planPoints: Double? { planRate.map { $0.doubleValue * 100 } }

    var body: some View {
        let bars = self.bars
        let scale = money.rateScale(planRate: planRate)
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
        let withoutRate: [Bar] = bars.filter { !$0.period.isEmpty && $0.rate == nil }
        return Chart {
            rateBars(rated, within: scale.domain)
            zeroRule()
            withoutRateDots(withoutRate, at: scale.domain.lowerBound)
            lastTwelveMonthsLine(linePoints, within: scale.domain)
            planRule()
            selectionRule(selectedPeriod)
        }
        .chartLegend(.hidden)
        .chartXSelection(value: $selectedDate)
        .chartXScale(domain: domain)
        .chartYScale(domain: scale.domain)
        .chartYAxis { Self.rateAxis(scale.ticks, locale: locale) }
        .chartXAxis { dateAxis(ticks) }
    }

    /// Each bar, an area from zero to its rate between its start and its
    /// end, drawn to the edge of the value axis's `domain` with a gap when
    /// its rate is beyond it; `key` keeps a bar's area apart from the
    /// others'.
    @ChartContentBuilder
    private func rateBars(_ bars: [Bar], within domain: ClosedRange<Double>) -> some ChartContent {
        ForEach(bars) { bar in
            AreaMark(x: .value("Date", bar.start), yStart: .value("From", 0.0),
                     yEnd: .value("Savings rate", bar.height(within: domain)), series: .value("Bar", bar.key))
                .foregroundStyle(Palette.color(for: Self.barColor).opacity(bar.opacity))
                .spokenValue(spokenRate(bar.rate ?? 0, within: domain))
            AreaMark(x: .value("Date", bar.end), yStart: .value("From", 0.0),
                     yEnd: .value("Savings rate", bar.height(within: domain)), series: .value("Bar", bar.key))
                .foregroundStyle(Palette.color(for: Self.barColor).opacity(bar.opacity))
                .spokenValue(spokenRate(bar.rate ?? 0, within: domain))
            if let gap = ChartCut.gap(bar.rate ?? 0, within: domain) {
                ChartCut.gapMark(from: bar.start, to: bar.end, at: gap, surface: surface)
            }
        }
    }

    @ChartContentBuilder
    private func zeroRule() -> some ChartContent {
        RuleMark(y: .value("Zero", 0.0))
            .foregroundStyle(Palette.axis)
            .lineStyle(StrokeStyle(lineWidth: 1))
    }

    /// Each period with money in and out but no rate, a dot at the value
    /// axis's `bottom` edge: nothing came in after tax, so it has no bar,
    /// yet what it spent counts in the line.
    @ChartContentBuilder
    private func withoutRateDots(_ bars: [Bar], at bottom: Double) -> some ChartContent {
        ForEach(bars) { bar in
            PointMark(x: .value("Date", bar.middle), y: .value("No rate", bottom))
                .foregroundStyle(Palette.color(for: Self.withoutRateColor).opacity(bar.opacity))
                .symbolSize(36)
        }
    }

    /// The rate over the 12 months ending at each month, a line for each
    /// run, so it breaks where those 12 months have no rate; a run of one
    /// is a dot. It's kept within the value axis's `domain`: where it runs
    /// past, the line goes along the edge, with a triangle at each month
    /// pointing past it (``ChartCut``).
    @ChartContentBuilder
    private func lastTwelveMonthsLine(_ points: [LinePoint], within domain: ClosedRange<Double>) -> some ChartContent {
        ForEach(points) { point in
            let rate = point.rate
            LineMark(x: .value("Date", point.middle),
                     y: .value("Rate over 12 months", PlanMoneyInOut.clamped(rate, to: domain)),
                     series: .value("Line", "Rate over 12 months \(point.run)"))
                .foregroundStyle(Palette.ink)
                .lineStyle(StrokeStyle(lineWidth: Metrics.lineWidth, lineCap: .round, lineJoin: .round))
                .spokenValue(spokenRate(rate, within: domain))
        }
        ForEach(points.filter { $0.isAlone && domain.contains($0.rate) }) { point in
            PointMark(x: .value("Date", point.middle), y: .value("Rate over 12 months", point.rate))
                .foregroundStyle(Palette.ink)
                .symbolSize(20)
        }
        ForEach(points.filter { !domain.contains($0.rate) }) { point in
            PointMark(x: .value("Date", point.middle),
                      y: .value("Rate over 12 months", PlanMoneyInOut.clamped(point.rate, to: domain)))
                .symbol { ChartCut.arrow(up: point.rate > domain.upperBound, color: Palette.ink) }
                .accessibilityHidden(true)
        }
    }

    /// What VoiceOver reads for a mark of `rate`, in percentage points: the
    /// real rate when it's beyond the value axis's `domain` and drawn cut,
    /// else `nil` for what's plotted.
    private func spokenRate(_ rate: Double, within domain: ClosedRange<Double>) -> String? {
        domain.contains(rate) ? nil : AmountFormat.percent(rate / 100, digits: 0, locale: locale)
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
        PlanSavingsRateCallout(money: money, period: period)
    }

    /// Faint gridlines at the scale's ticks, labelled as percentages ("30%")
    /// in `locale`.
    private static func rateAxis(_ ticks: [Double], locale: Locale) -> some AxisContent {
        AxisMarks(position: .leading, values: ticks) { value in
            AxisGridLine(stroke: StrokeStyle(lineWidth: 0.5))
                .foregroundStyle(Palette.gridline)
            AxisValueLabel {
                if let points = value.as(Double.self) {
                    Text(verbatim: AmountFormat.percent(points / 100, digits: 0, locale: locale))
                        .font(.caption2)
                        .monospacedDigit()
                        .foregroundStyle(Palette.mutedInk)
                }
            }
        }
    }

    private func summary(_ bars: [Bar]) -> ChartSummary {
        let locale = self.locale
        let unit = money.grain == .months ? "month" : "year"
        func day(_ bar: Bar) -> String { AmountFormat.mediumDate(bar.period.through, locale: locale) }
        var series = [ChartSummary.Series(
            name: "Savings rate", points: bars.compactMap { bar in bar.rate.map { (day(bar), $0) } })]
        let rolling = bars.compactMap { bar in bar.lastTwelveMonths.map { (day(bar), $0) } }
        if !rolling.isEmpty { series.append(ChartSummary.Series(name: "Rate over 12 months", points: rolling)) }
        var text = "What you saved of what came in, each \(unit)."
        if let line = money.lineWords() {
            text += " " + line
        }
        if let withoutRate = money.withoutRateWords(locale: locale) {
            text += " " + withoutRate
        }
        if let planRate {
            text += " Your plan's savings rate is \(AmountFormat.percent(planRate, digits: 0, locale: locale))."
        }
        return ChartSummary(title: "Savings rate", summary: text, xTitle: "Date", yTitle: "Savings rate",
                            series: series,
                            describeValue: { AmountFormat.percent($0 / 100, digits: 0, locale: locale) })
    }
}

/// The key of *Savings rate*: the rate over 12 months when its line is
/// drawn, "No rate" for the dot of a period without one when there's one,
/// the plan's rate ("Your plan's 28%") when there's one, and a note when a
/// bar or the line is cut at the edge.
struct PlanSavingsRateLegend: View {
    let money: PlanMoneyInOut
    var planRate: Decimal?
    /// Whether a bar or the line is beyond the value axis
    /// (``PlanMoneyInOut/cutsRates(planRate:)``).
    var cuts = false

    @Environment(\.locale) private var locale

    var body: some View {
        var items = [ChartLegendItem(name: "Savings rate", swatch: .bar(PlanSavingsRateChart.barColor))]
        if money.hasLastTwelveMonths {
            items.append(ChartLegendItem(name: "Rate over 12 months", swatch: .line(.ink, dashed: false)))
        }
        if !money.countedWithoutRate.isEmpty {
            items.append(ChartLegendItem(name: "No rate", swatch: .dot(PlanSavingsRateChart.withoutRateColor)))
        }
        if let planRate {
            let rate = AmountFormat.percent(planRate, digits: 0, locale: locale)
            items.append(ChartLegendItem(name: "Your plan's \(rate)",
                                         swatch: .line(.taxes, dashed: true)))
        }
        return ChartLegendRow(items: items, note: cuts ? "Cut at the edge" : nil)
    }
}

/// What a period of *Savings rate* reads where the pointer or a finger is
/// (UI.md, "Trends"): its last day, with "so far" or what it covers; its
/// savings rate with what came in and what was saved, which it's worked out
/// from ("Savings rate 34%", "Came in 4.100 €", "Saved 1.500 €"); then,
/// where the line has a point, the rate over the 12 months ending there
/// with theirs ("Rate over 12 months 31%", "Came in 45.800 €", "Saved
/// 14.200 €"), so a point of the line can be checked. A rate is "–" when
/// there's none, with why under it ("Nothing came in", "Less than nothing
/// came in", "More tax than came in"). Rates stay with the eye; amounts
/// hide.
struct PlanSavingsRateCallout: View {
    let money: PlanMoneyInOut
    let period: MoneyInOutPeriod

    @Environment(\.locale) private var locale

    var body: some View {
        ChartCallout {
            ChartCalloutDate(period.through.dateValue, detail: money.calloutDetail(period, locale: locale))
            if let savings = period.savings {
                rate("Savings rate", savings, swatch: .bar)
            } else {
                Text("No money in and out recorded")
                    .font(.caption2)
                    .foregroundStyle(Palette.secondaryInk)
            }
            if let lastTwelveMonths = period.lastTwelveMonths {
                rate("Rate over 12 months", lastTwelveMonths, swatch: .line)
                    .padding(.top, 2)
            }
        }
    }

    private enum Swatch {
        case bar
        case line
    }

    /// A rate's row, "Savings rate 34%", with its swatch on the chart, then
    /// what came in and what was saved.
    private func rate(_ title: String, _ savings: SavingsRate, swatch: Swatch) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            HStack(spacing: 4) {
                switch swatch {
                case .bar:
                    RoundedRectangle(cornerRadius: 1)
                        .fill(Palette.color(for: PlanSavingsRateChart.barColor))
                        .frame(width: 6, height: 8)
                case .line:
                    Capsule()
                        .fill(Palette.ink)
                        .frame(width: 8, height: 2)
                }
                Text(title)
                    .foregroundStyle(Palette.secondaryInk)
                Spacer(minLength: 4)
                Text(verbatim: savings.rate.map { AmountFormat.percent($0, digits: 0, locale: locale) } ?? "–")
                    .monospacedDigit()
            }
            .font(.caption2)
            if let why = savings.noRate {
                Text(why.words)
                    .font(.caption2)
                    .foregroundStyle(Palette.secondaryInk)
            }
            ChartCalloutRow("Came in", amount: savings.income.doubleValue, currency: money.currency)
            ChartCalloutRow("Saved", amount: savings.saved.doubleValue, currency: money.currency)
        }
    }
}
