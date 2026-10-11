import Charts
import Model
import SwiftUI
import Tracker

/// Trends' *Money in and out* (UI.md, "Trends"): per month or year, what
/// came in and what went out as a pair of bars from zero, and what was kept
/// as a dot, counted as the savings rate counts them (came in and kept
/// include the pension contributions), in the base currency at each value's
/// date. A dashed rule at the plan's spending while working, for a month or
/// a year. A period whose values cover more than it, after a skipped
/// check-in, has hatched bars, and its callout says what they cover. The
/// current month or year is drawn lighter ("so far"). While amounts are
/// hidden the value axis reads in multiples of a period's average came in.
struct PlanMoneyInOutChart: View {
    let money: PlanMoneyInOut
    /// The plan's spending while working, for a month or a year; `nil` when
    /// it's past working.
    var planSpending: Decimal?

    @State private var selectedDate: Date?
    @State private var width: CGFloat = ChartStyle.defaultWidth
    @Environment(\.redactionReasons) private var redactionReasons

    static let height: CGFloat = 200

    /// Came in: the accent; went out: orange; kept: ink.
    static let cameInColor = ChartColor.accent
    static let wentOutColor = ChartColor.series(1)
    static let keptColor = ChartColor.ink

    private var hidesAmounts: Bool { redactionReasons.hidesAmounts }

    /// One period's pair of bars and its dot.
    private struct Pair: Identifiable {
        var period: MoneyInOutPeriod
        var cameInStart: Date
        var cameInEnd: Date
        var wentOutStart: Date
        var wentOutEnd: Date
        var middle: Date
        var cameIn: Double
        var wentOut: Double
        var kept: Double
        var isSoFar: Bool
        var coversMore: Bool

        var id: Date { middle }
    }

    private var pairs: [Pair] {
        money.counted.map { period in
            let span = money.timeSpan(of: period)
            return Pair(period: period, cameInStart: PlanMoneyInOut.date(0.12, across: span),
                        cameInEnd: PlanMoneyInOut.date(0.47, across: span),
                        wentOutStart: PlanMoneyInOut.date(0.53, across: span),
                        wentOutEnd: PlanMoneyInOut.date(0.88, across: span), middle: money.middle(of: period),
                        cameIn: period.cameIn.doubleValue, wentOut: period.moneyOut.doubleValue,
                        kept: period.kept.doubleValue, isSoFar: money.isSoFar(period),
                        coversMore: money.coversMore(period))
        }
    }

    var body: some View {
        let pairs = self.pairs
        let scale = AmountScale(values: pairs.flatMap { [$0.cameIn, $0.wentOut, $0.kept] }
            + [planSpending?.doubleValue].compactMap { $0 })
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
        let color = Palette.color(for: role).opacity(pair.isSoFar ? soFarOpacity : 1)
        return pair.coversMore ? AnyShapeStyle(ChartHatch.style(color)) : AnyShapeStyle(color)
    }

    private func chart(_ pairs: [Pair], scale: AmountScale, domain: ClosedRange<Date>) -> some View {
        Chart {
            ForEach(pairs) { pair in
                BarMark(xStart: .value("Start", pair.cameInStart), xEnd: .value("End", pair.cameInEnd),
                        yStart: .value("Zero", 0.0), yEnd: .value("Came in", pair.cameIn))
                    .foregroundStyle(Self.fill(Self.cameInColor, of: pair))
                    .cornerRadius(2)
                    .spokenValueHidden(hidesAmounts)
                BarMark(xStart: .value("Start", pair.wentOutStart), xEnd: .value("End", pair.wentOutEnd),
                        yStart: .value("Zero", 0.0), yEnd: .value("Went out", pair.wentOut))
                    .foregroundStyle(Self.fill(Self.wentOutColor, of: pair))
                    .cornerRadius(2)
                    .spokenValueHidden(hidesAmounts)
            }
            RuleMark(y: .value("Zero", 0.0))
                .foregroundStyle(Palette.axis)
                .lineStyle(StrokeStyle(lineWidth: 1))
            if let planSpending {
                RuleMark(y: .value("Your plan's spending while working", planSpending.doubleValue))
                    .foregroundStyle(Palette.secondaryInk)
                    .lineStyle(StrokeStyle(lineWidth: 1.5, dash: [4, 3]))
                    .spokenValueHidden(hidesAmounts)
            }
            ForEach(pairs) { pair in
                PointMark(x: .value("Date", pair.middle), y: .value("Kept", pair.kept))
                    .foregroundStyle(Palette.stroke(for: Self.keptColor).opacity(pair.isSoFar ? Self.soFarOpacity : 1))
                    .symbolSize(36)
                    .spokenValueHidden(hidesAmounts)
            }
            if let selectedDate, let period = money.period(nearest: selectedDate) {
                RuleMark(x: .value("Date", money.middle(of: period)))
                    .foregroundStyle(Palette.secondaryInk)
                    .lineStyle(StrokeStyle(lineWidth: 1))
                    .annotation(position: .top, spacing: 4,
                                overflowResolution: .init(x: .fit(to: .chart), y: .fit(to: .chart))) {
                        PlanMoneyInOutCallout(money: money, period: period)
                    }
            }
        }
        .chartLegend(.hidden)
        .chartXSelection(value: $selectedDate)
        .chartXScale(domain: domain)
        .chartYScale(domain: scale.domain)
        .chartYAxis { amountAxis(hidesAmounts: hidesAmounts, scale: scale, relativeTo: money.relativeBase) }
        .chartXAxis { dateAxis(TimeTicks(domain: domain, plotWidth: max(Double(width) - 48, 1))) }
    }

    private func summary(_ pairs: [Pair]) -> ChartSummary {
        func spoken(_ value: KeyPath<Pair, Double>) -> [(String, Double)] {
            pairs.map { (AmountFormat.mediumDate($0.period.through), $0[keyPath: value]) }
        }
        let unit = money.grain == .months ? "month" : "year"
        return ChartSummary(
            title: "Money in and out",
            summary: "What came in, what went out and what you kept, each \(unit).",
            xTitle: "Date", yTitle: "Amount",
            series: [
                ChartSummary.Series(name: "Came in", points: spoken(\.cameIn)),
                ChartSummary.Series(name: "Went out", points: spoken(\.wentOut)),
                ChartSummary.Series(name: "Kept", points: spoken(\.kept)),
            ],
            describeValue: ChartStyle.spokenAmount(currency: money.currency, hidden: hidesAmounts))
    }
}

/// The key of *Money in and out*: came in, went out and kept; the plan's
/// spending while working when it's drawn; and the hatching when a period
/// covers more than itself.
struct PlanMoneyInOutLegend: View {
    let money: PlanMoneyInOut
    let showsPlanSpending: Bool

    var body: some View {
        var items = [
            ChartLegendItem(name: "Came in", swatch: .bar(PlanMoneyInOutChart.cameInColor)),
            ChartLegendItem(name: "Went out", swatch: .bar(PlanMoneyInOutChart.wentOutColor)),
            ChartLegendItem(name: "Kept", swatch: .dot(PlanMoneyInOutChart.keptColor)),
        ]
        if showsPlanSpending {
            items.append(ChartLegendItem(name: "Your plan's spending while working",
                                         swatch: .line(.taxes, dashed: true)))
        }
        if money.hasCoversMore {
            items.append(ChartLegendItem(name: money.grain == .months ? "More than a month" : "More than a year",
                                         swatch: .hatchedBar(.neutral)))
        }
        return ChartLegendRow(items: items)
    }
}

/// What a period of *Savings rate* or *Money in and out* reads where the
/// pointer or a finger is (UI.md, "Trends"): its last day, with "so far"
/// or what it covers, then its rows: "Savings rate 34%", "Last 12 months
/// 31%", "Came in 4.100 €", "Went out 2.600 €", "Kept 1.500 €". Rates stay
/// with the eye; amounts hide.
struct PlanMoneyInOutCallout: View {
    let money: PlanMoneyInOut
    let period: MoneyInOutPeriod

    @Environment(\.locale) private var locale

    var body: some View {
        ChartCallout {
            ChartCalloutDate(period.through.dateValue, detail: detail)
            if period.isEmpty {
                Text("No money in and out recorded")
                    .font(.caption2)
                    .foregroundStyle(Palette.secondaryInk)
            } else {
                if let rate = period.rate {
                    rateRow("Savings rate", rate)
                }
                if let lastTwelveMonths = period.lastTwelveMonths?.rate {
                    rateRow("Last 12 months", lastTwelveMonths)
                }
                ChartCalloutRow("Came in", swatch: Palette.color(for: PlanMoneyInOutChart.cameInColor),
                                amount: period.cameIn.doubleValue, currency: money.currency)
                ChartCalloutRow("Went out", swatch: Palette.color(for: PlanMoneyInOutChart.wentOutColor),
                                amount: period.moneyOut.doubleValue, currency: money.currency)
                ChartCalloutRow("Kept", swatch: Palette.stroke(for: PlanMoneyInOutChart.keptColor),
                                amount: period.kept.doubleValue, currency: money.currency)
            }
        }
    }

    /// "so far", "covers Sep – Oct", or both.
    private var detail: String? {
        let parts = [money.isSoFar(period) ? "so far" : nil, money.coverWords(period, locale: locale)]
            .compactMap { $0 }
        return parts.isEmpty ? nil : parts.joined(separator: " · ")
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
            PlanSavingsRateLegend(showsLastTwelveMonths: money.hasLastTwelveMonths, planRate: planRate)
            PlanSavingsRateChart(money: money, planRate: planRate)
        }
        Card("Money in and out") {
            PlanMoneyInOutLegend(money: money, showsPlanSpending: true)
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
