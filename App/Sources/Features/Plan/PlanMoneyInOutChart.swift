import Charts
import Model
import SwiftUI
import Tracker

/// Trends' *Money in and out* (UI.md, "Look Back"): per month or year, what
/// came in and what was spent as a pair of bars from zero, and what was saved
/// as a dot, counted as the savings rate counts them (came in and saved
/// include the pension contributions), in the base currency at each value's
/// date. A dashed rule at the plan's spending while working, for a month or
/// a year. A period whose values cover more than it, after a skipped
/// check-in, has hatched bars, and its callout says what they cover. The
/// current month or year is drawn lighter ("so far"). The value axis fits
/// what's typical around each period and the plan's rule
/// (``PlanMoneyInOut/amountAxisValues(planSpending:)``); a bar beyond is
/// drawn to the axis's edge with a gap, a dot as a triangle (``ChartCut``),
/// and the callout and VoiceOver read the real amounts. While amounts are
/// hidden the value axis reads in multiples of what typically came in in a
/// period (``PlanMoneyInOut/relativeBase``).
struct PlanMoneyInOutChart: View {
    let money: PlanMoneyInOut
    /// The plan's spending while working, for a month or a year; `nil` when
    /// it's past working.
    var planSpending: Decimal?

    @State private var selectedDate: Date?
    @State private var width: CGFloat = ChartStyle.defaultWidth
    @Environment(\.redactionReasons) private var redactionReasons
    @Environment(\.locale) private var locale
    @Environment(\.chartSurface) private var surface

    static let height: CGFloat = 200

    /// Came in: the accent; spent: orange; saved: ink.
    static let cameInColor = ChartColor.accent
    static let spentColor = ChartColor.series(1)
    static let savedColor = ChartColor.ink

    private var hidesAmounts: Bool { redactionReasons.hidesAmounts }

    /// One period's pair of bars and its dot.
    private struct Pair: Identifiable {
        var period: MoneyInOutPeriod
        var cameInStart: Date
        var cameInEnd: Date
        var spentStart: Date
        var spentEnd: Date
        var middle: Date
        var cameIn: Double
        var spent: Double
        var saved: Double
        var isSoFar: Bool
        var coversMore: Bool

        var id: Date { middle }
        /// Keeps the pair's areas apart from the others'.
        var key: String { period.from.description }
    }

    private var pairs: [Pair] {
        money.counted.map { period in
            let span = money.timeSpan(of: period)
            return Pair(period: period, cameInStart: PlanMoneyInOut.date(0.12, across: span),
                        cameInEnd: PlanMoneyInOut.date(0.47, across: span),
                        spentStart: PlanMoneyInOut.date(0.53, across: span),
                        spentEnd: PlanMoneyInOut.date(0.88, across: span), middle: money.middle(of: period),
                        cameIn: period.cameIn.doubleValue, spent: period.spent.doubleValue,
                        saved: period.saved.doubleValue, isSoFar: money.isSoFar(period),
                        coversMore: money.coversMore(period))
        }
    }

    var body: some View {
        let pairs = self.pairs
        let scale = money.amountScale(planSpending: planSpending)
        let domain = money.domain ?? (Date.now...Date.now.addingTimeInterval(31 * 86_400))
        chart(pairs, scale: scale, domain: domain)
            .frame(height: Self.height)
            .measuringWidth($width)
            .accessibilityChartDescriptor(summary(pairs))
            .privacySensitiveInFeedback()
    }

    /// How much of its colour the "so far" period keeps.
    private static let soFarOpacity = 0.45

    /// A bar's fill: its colour, hatched when its period covers more, and
    /// lighter while it's so far.
    private static func fill(_ role: ChartColor, of pair: Pair) -> AnyShapeStyle {
        let color: Color = Palette.color(for: role).opacity(pair.isSoFar ? soFarOpacity : 1)
        if pair.coversMore {
            return AnyShapeStyle(ChartHatch.style(color))
        }
        return AnyShapeStyle(color)
    }

    /// The period nearest the pointer or a finger.
    private var selectedPeriod: MoneyInOutPeriod? {
        guard let selectedDate else { return nil }
        return money.period(nearest: selectedDate)
    }

    private func chart(_ pairs: [Pair], scale: AmountScale, domain: ClosedRange<Date>) -> some View {
        let ticks = TimeTicks(domain: domain, plotWidth: max(Double(width) - 48, 1))
        let base: Double? = money.relativeBase
        return Chart {
            cameInBars(pairs, within: scale.domain)
            spentBars(pairs, within: scale.domain)
            zeroRule()
            planRule()
            savedDots(pairs, within: scale.domain)
            selectionRule(selectedPeriod)
        }
        .chartLegend(.hidden)
        .chartXSelection(value: $selectedDate)
        .chartXScale(domain: domain)
        .chartYScale(domain: scale.domain)
        .chartYAxis { amountAxis(hidesAmounts: hidesAmounts, scale: scale, relativeTo: base) }
        .chartXAxis { dateAxis(ticks) }
    }

    /// Each period's came in, an area from zero between the bar's start and
    /// end, drawn to the edge of the value axis's `domain` with a gap when
    /// it's beyond it; `key` keeps a bar's area apart from the others'.
    @ChartContentBuilder
    private func cameInBars(_ pairs: [Pair], within domain: ClosedRange<Double>) -> some ChartContent {
        ForEach(pairs) { pair in
            let height = PlanMoneyInOut.clamped(pair.cameIn, to: domain)
            AreaMark(x: .value("Date", pair.cameInStart), yStart: .value("From", 0.0),
                     yEnd: .value("Came in", height), series: .value("Bar", "Came in " + pair.key))
                .foregroundStyle(Self.fill(Self.cameInColor, of: pair))
                .spokenValue(spokenAmount(pair.cameIn, within: domain))
            AreaMark(x: .value("Date", pair.cameInEnd), yStart: .value("From", 0.0),
                     yEnd: .value("Came in", height), series: .value("Bar", "Came in " + pair.key))
                .foregroundStyle(Self.fill(Self.cameInColor, of: pair))
                .spokenValue(spokenAmount(pair.cameIn, within: domain))
            if let gap = ChartCut.gap(pair.cameIn, within: domain) {
                ChartCut.gapMark(from: pair.cameInStart, to: pair.cameInEnd, at: gap, surface: surface)
            }
        }
    }

    /// What each period spent, drawn as ``cameInBars(_:within:)`` draws
    /// came in.
    @ChartContentBuilder
    private func spentBars(_ pairs: [Pair], within domain: ClosedRange<Double>) -> some ChartContent {
        ForEach(pairs) { pair in
            let height = PlanMoneyInOut.clamped(pair.spent, to: domain)
            AreaMark(x: .value("Date", pair.spentStart), yStart: .value("From", 0.0),
                     yEnd: .value("Spent", height), series: .value("Bar", "Spent " + pair.key))
                .foregroundStyle(Self.fill(Self.spentColor, of: pair))
                .spokenValue(spokenAmount(pair.spent, within: domain))
            AreaMark(x: .value("Date", pair.spentEnd), yStart: .value("From", 0.0),
                     yEnd: .value("Spent", height), series: .value("Bar", "Spent " + pair.key))
                .foregroundStyle(Self.fill(Self.spentColor, of: pair))
                .spokenValue(spokenAmount(pair.spent, within: domain))
            if let gap = ChartCut.gap(pair.spent, within: domain) {
                ChartCut.gapMark(from: pair.spentStart, to: pair.spentEnd, at: gap, surface: surface)
            }
        }
    }

    @ChartContentBuilder
    private func zeroRule() -> some ChartContent {
        RuleMark(y: .value("Zero", 0.0))
            .foregroundStyle(Palette.axis)
            .lineStyle(StrokeStyle(lineWidth: 1))
    }

    /// The plan's spending while working, dashed.
    @ChartContentBuilder
    private func planRule() -> some ChartContent {
        if let planSpending {
            RuleMark(y: .value("Your plan's spending while working", planSpending.doubleValue))
                .foregroundStyle(Palette.secondaryInk)
                .lineStyle(StrokeStyle(lineWidth: 1.5, dash: [4, 3]))
                .spokenValueHidden(hidesAmounts)
        }
    }

    /// What each period saved, a dot; beyond the value axis's `domain`, a
    /// triangle at its edge pointing past it.
    @ChartContentBuilder
    private func savedDots(_ pairs: [Pair], within domain: ClosedRange<Double>) -> some ChartContent {
        ForEach(pairs) { pair in
            let color = Palette.stroke(for: Self.savedColor).opacity(pair.isSoFar ? Self.soFarOpacity : 1)
            if domain.contains(pair.saved) {
                PointMark(x: .value("Date", pair.middle), y: .value("Saved", pair.saved))
                    .foregroundStyle(color)
                    .symbolSize(36)
                    .spokenValue(spokenAmount(pair.saved, within: domain))
            } else {
                PointMark(x: .value("Date", pair.middle),
                          y: .value("Saved", PlanMoneyInOut.clamped(pair.saved, to: domain)))
                    .symbol { ChartCut.arrow(up: pair.saved > domain.upperBound, color: color) }
                    .spokenValue(spokenAmount(pair.saved, within: domain))
            }
        }
    }

    /// What VoiceOver reads for a mark of `value`: "Amount hidden" while
    /// amounts are hidden, the real amount when it's beyond the value
    /// axis's `domain` and drawn cut, else `nil` for what's plotted.
    private func spokenAmount(_ value: Double, within domain: ClosedRange<Double>) -> String? {
        if hidesAmounts { return ChartStyle.spokenHiddenAmount }
        guard !domain.contains(value) else { return nil }
        return ChartStyle.spokenAmount(currency: money.currency, hidden: false)(value)
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

    private func summary(_ pairs: [Pair]) -> ChartSummary {
        let locale = self.locale
        func spoken(_ value: KeyPath<Pair, Double>) -> [(String, Double)] {
            pairs.map { (AmountFormat.mediumDate($0.period.through, locale: locale), $0[keyPath: value]) }
        }
        let unit = money.grain == .months ? "month" : "year"
        return ChartSummary(
            title: "Money in and out",
            summary: "What came in, what was spent and what you saved, each \(unit).",
            xTitle: "Date", yTitle: "Amount",
            series: [
                ChartSummary.Series(name: "Came in", points: spoken(\.cameIn)),
                ChartSummary.Series(name: "Spent", points: spoken(\.spent)),
                ChartSummary.Series(name: "Saved", points: spoken(\.saved)),
            ],
            describeValue: ChartStyle.spokenAmount(currency: money.currency, hidden: hidesAmounts))
    }
}

/// The key of *Money in and out*: came in, spent and saved; the plan's
/// spending while working when it's drawn; the hatching when a period
/// covers more than itself; and a note when a value is cut at the edge.
struct PlanMoneyInOutLegend: View {
    let money: PlanMoneyInOut
    let showsPlanSpending: Bool
    /// Whether a value is beyond the value axis
    /// (``PlanMoneyInOut/cutsAmounts(planSpending:)``).
    var cuts = false

    var body: some View {
        var items = [
            ChartLegendItem(name: "Came in", swatch: .bar(PlanMoneyInOutChart.cameInColor)),
            ChartLegendItem(name: "Spent", swatch: .bar(PlanMoneyInOutChart.spentColor)),
            ChartLegendItem(name: "Saved", swatch: .dot(PlanMoneyInOutChart.savedColor)),
        ]
        if showsPlanSpending {
            items.append(ChartLegendItem(name: "Your plan's spending while working",
                                         swatch: .line(.taxes, dashed: true)))
        }
        if money.hasCoversMore {
            items.append(ChartLegendItem(name: money.grain == .months ? "More than a month" : "More than a year",
                                         swatch: .hatchedBar(.neutral)))
        }
        return ChartLegendRow(items: items, note: cuts ? "Cut at the edge" : nil)
    }
}

/// What a period of *Money in and out* reads where the
/// pointer or a finger is (UI.md, "Look Back"): its last day, with "so far"
/// or what it covers, then its rows: "Savings rate 34%", "Rate over 12
/// months 31%", "Came in 4.100 €", "Spent 2.600 €", "Saved 1.500 €". Rates
/// stay with the eye; amounts hide.
struct PlanMoneyInOutCallout: View {
    let money: PlanMoneyInOut
    let period: MoneyInOutPeriod

    @Environment(\.locale) private var locale

    var body: some View {
        ChartCallout {
            ChartCalloutDate(period.through.dateValue, detail: money.calloutDetail(period, locale: locale))
            if period.isEmpty {
                Text("No money in and out recorded")
                    .font(.caption2)
                    .foregroundStyle(Palette.secondaryInk)
            } else {
                if let rate = period.rate {
                    rateRow("Savings rate", rate)
                }
                if let lastTwelveMonths = period.lastTwelveMonths?.rate {
                    rateRow("Rate over 12 months", lastTwelveMonths)
                }
                ChartCalloutRow("Came in", swatch: Palette.color(for: PlanMoneyInOutChart.cameInColor),
                                amount: period.cameIn.doubleValue, currency: money.currency)
                ChartCalloutRow("Spent", swatch: Palette.color(for: PlanMoneyInOutChart.spentColor),
                                amount: period.spent.doubleValue, currency: money.currency)
                ChartCalloutRow("Saved", swatch: Palette.stroke(for: PlanMoneyInOutChart.savedColor),
                                amount: period.saved.doubleValue, currency: money.currency)
            }
        }
    }

    /// A rate in a row, as an amount's row reads: "Savings rate 34%".
    private func rateRow(_ title: String, _ rate: Decimal) -> some View {
        HStack(spacing: 4) {
            Text(title)
                .foregroundStyle(Palette.secondaryInk)
            Spacer(minLength: 4)
            Text(verbatim: AmountFormat.percent(rate, digits: 0, locale: locale))
                .monospacedDigit()
        }
        .font(.caption2)
    }
}

#Preview("Savings rate, money in and out") {
    let valuator = PreviewLibrary.valuator
    let end = PreviewLibrary.latestCheckIn
    let money = PlanMoneyInOut(valuator.moneyInOutSeries(.months, through: end), from: nil,
                               firstRecord: valuator.firstValuationDate(in: .planAssets), through: end)
    let planRate = Decimal(string: "0.1")
    VStack(spacing: Metrics.l) {
        Card("Savings rate") {
            PlanSavingsRateLegend(money: money, planRate: planRate,
                                  cuts: money.cutsRates(planRate: planRate))
            PlanSavingsRateChart(money: money, planRate: planRate)
        }
        Card("Money in and out") {
            PlanMoneyInOutLegend(money: money, showsPlanSpending: true, cuts: money.cutsAmounts(planSpending: 3_000))
            PlanMoneyInOutChart(money: money, planSpending: 3_000)
        }
        Card("Amounts hidden") {
            PlanMoneyInOutChart(money: money, planSpending: 3_000)
                .redacted(reason: .privacy)
        }
    }
    .padding()
    .background(Palette.page)
    .previewEnvironment()
}
