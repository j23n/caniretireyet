import Charts
import Model
import SwiftUI
import Tracker

/// So far's *Money in and out* (UI.md, "So far"): per month, two bars from
/// zero (``MoneyInOutBars``): what came in, money in with the pension on
/// top, beside what went out, what was spent with the tax on top, in the
/// colours of the year's pay tile. The gap between them is what was left
/// over. A part below zero (a tax refund) hangs below the zero line. In
/// the base currency at each value's date. A period whose values cover
/// more than it, after a skipped check-in, has hatched bars, and its
/// callout says what they cover. The current month has a dashed outline
/// marked "so far". The value axis fits what's typical around each period
/// (``PlanMoneyInOut/amountAxisValues(planSpending:)``); a bar beyond is
/// drawn to the axis's edge with a gap (``ChartCut``), and the callout and
/// VoiceOver read the real amounts. While amounts are hidden the value axis
/// reads in multiples of what typically came in in a period
/// (``PlanMoneyInOut/relativeBase``).
struct PlanMoneyInOutChart: View {
    let money: PlanMoneyInOut

    @State private var selectedDate: Date?
    @State private var width: CGFloat = ChartStyle.defaultWidth
    @Environment(\.redactionReasons) private var redactionReasons
    @Environment(\.locale) private var locale
    @Environment(\.chartSurface) private var surface

    static let height: CGFloat = 200

    /// Came in and the pension: green, the pension lighter; spent and the
    /// tax: orange, spent lighter. As the pay tile has them
    /// (``TodayMovedLine/Kind/color``).
    static let cameInColor = ChartColor.series(5)
    static let spentColor = ChartColor.series(1)
    /// How much of its colour the lighter part of a bar keeps.
    static let lighterOpacity = 0.5

    /// A part's colour, the pay tile's.
    static func color(_ part: MoneyInOutBars.Part) -> Color {
        switch part {
        case .moneyIn: TodayMovedLine.Kind.cameIn.color
        case .pension: TodayMovedLine.Kind.pension.color
        case .spent: TodayMovedLine.Kind.spent.color
        case .tax: TodayMovedLine.Kind.tax.color
        }
    }

    /// A part's name, as the legend and the callout say it.
    static func name(_ part: MoneyInOutBars.Part) -> String {
        switch part {
        case .moneyIn: "Came in"
        case .pension: "Pension"
        case .spent: "Spent"
        case .tax: "Tax"
        }
    }

    private var hidesAmounts: Bool { redactionReasons.hidesAmounts }

    /// One period's pair of bars.
    private struct Pair: Identifiable {
        var period: MoneyInOutPeriod
        var bars: MoneyInOutBars
        var cameInStart: Date
        var cameInEnd: Date
        var wentOutStart: Date
        var wentOutEnd: Date
        var outlineStart: Date
        var outlineEnd: Date
        var middle: Date
        var isSoFar: Bool
        var coversMore: Bool

        var id: Date { middle }
        /// Keeps the pair's areas apart from the others'.
        var key: String { period.from.description }
    }

    private var pairs: [Pair] {
        money.counted.compactMap { period in
            guard let bars = period.bars else { return nil }
            let span = money.timeSpan(of: period)
            return Pair(period: period, bars: bars,
                        cameInStart: PlanMoneyInOut.date(0.12, across: span),
                        cameInEnd: PlanMoneyInOut.date(0.47, across: span),
                        wentOutStart: PlanMoneyInOut.date(0.53, across: span),
                        wentOutEnd: PlanMoneyInOut.date(0.88, across: span),
                        outlineStart: PlanMoneyInOut.date(0.05, across: span),
                        outlineEnd: PlanMoneyInOut.date(0.95, across: span), middle: money.middle(of: period),
                        isSoFar: money.isSoFar(period), coversMore: money.coversMore(period))
        }
    }

    var body: some View {
        let pairs = self.pairs
        let scale = money.amountScale(planSpending: nil)
        let domain = money.domain ?? (Date.now...Date.now.addingTimeInterval(31 * 86_400))
        chart(pairs, scale: scale, domain: domain)
            .frame(height: Self.height)
            .measuringWidth($width)
            .accessibilityChartDescriptor(summary(pairs))
            .privacySensitiveInFeedback()
    }

    /// A part's fill: its colour, hatched when its period covers more.
    private static func fill(_ part: MoneyInOutBars.Part, of pair: Pair) -> AnyShapeStyle {
        let color = Self.color(part)
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
            ForEach(pairs) { pair in
                bar(pair.bars.cameIn, from: pair.cameInStart, to: pair.cameInEnd, of: pair, within: scale.domain)
                bar(pair.bars.wentOut, from: pair.wentOutStart, to: pair.wentOutEnd, of: pair,
                    within: scale.domain)
            }
            zeroRule()
            soFarOutline(pairs.first(where: \.isSoFar), within: scale.domain)
            selectionRule(selectedPeriod)
        }
        .chartLegend(.hidden)
        .chartXSelection(value: $selectedDate)
        .chartXScale(domain: domain)
        .chartYScale(domain: scale.domain)
        .chartYAxis { amountAxis(hidesAmounts: hidesAmounts, scale: scale, relativeTo: base) }
        .chartXAxis { dateAxis(ticks) }
    }

    /// One bar of `pair`: each of its `segments` an area from `start` to
    /// `end`, kept within the value axis's `domain`, with a gap where the
    /// bar goes beyond it; the part's name and the pair's `key` keep an
    /// area apart from the others.
    @ChartContentBuilder
    private func bar(_ segments: [MoneyInOutBars.Segment], from start: Date, to end: Date, of pair: Pair,
                     within domain: ClosedRange<Double>) -> some ChartContent {
        ForEach(segments, id: \.self) { segment in
            let low = PlanMoneyInOut.clamped(min(segment.from, segment.to).doubleValue, to: domain)
            let high = PlanMoneyInOut.clamped(max(segment.from, segment.to).doubleValue, to: domain)
            let series = Self.name(segment.part) + " " + pair.key
            AreaMark(x: .value("Date", start), yStart: .value("From", low), yEnd: .value("To", high),
                     series: .value("Bar", series))
                .foregroundStyle(Self.fill(segment.part, of: pair))
                .spokenValue(spokenAmount(segment.length.doubleValue, within: domain))
            AreaMark(x: .value("Date", end), yStart: .value("From", low), yEnd: .value("To", high),
                     series: .value("Bar", series))
                .foregroundStyle(Self.fill(segment.part, of: pair))
                .spokenValue(spokenAmount(segment.length.doubleValue, within: domain))
        }
        if let top = segments.map({ max($0.from, $0.to) }).max(),
           let gap = ChartCut.gap(top.doubleValue, within: domain) {
            ChartCut.gapMark(from: start, to: end, at: gap, surface: surface)
        }
        if let bottom = segments.map({ min($0.from, $0.to) }).min(),
           let gap = ChartCut.gap(bottom.doubleValue, within: domain) {
            ChartCut.gapMark(from: start, to: end, at: gap, surface: surface)
        }
    }

    @ChartContentBuilder
    private func zeroRule() -> some ChartContent {
        RuleMark(y: .value("Zero", 0.0))
            .foregroundStyle(Palette.axis)
            .lineStyle(StrokeStyle(lineWidth: 1))
    }

    /// A dashed outline around the month that isn't over yet, "so far"
    /// over it.
    @ChartContentBuilder
    private func soFarOutline(_ pair: Pair?, within domain: ClosedRange<Double>) -> some ChartContent {
        if let pair {
            let pad = (domain.upperBound - domain.lowerBound) * 0.02
            let top = min(pair.bars.top.doubleValue + pad, domain.upperBound)
            let bottom = max(pair.bars.bottom.doubleValue - pad, domain.lowerBound)
            let style = StrokeStyle(lineWidth: 1, dash: [3, 2])
            RuleMark(xStart: .value("Date", pair.outlineStart), xEnd: .value("Date", pair.outlineEnd),
                     y: .value("So far", top))
                .foregroundStyle(Palette.secondaryInk)
                .lineStyle(style)
                .annotation(position: .top, spacing: 2) {
                    Text("so far")
                        .font(.caption2)
                        .foregroundStyle(Palette.secondaryInk)
                }
                .accessibilityHidden(true)
            RuleMark(xStart: .value("Date", pair.outlineStart), xEnd: .value("Date", pair.outlineEnd),
                     y: .value("So far", bottom))
                .foregroundStyle(Palette.secondaryInk)
                .lineStyle(style)
                .accessibilityHidden(true)
            RuleMark(x: .value("Date", pair.outlineStart), yStart: .value("So far", bottom),
                     yEnd: .value("So far", top))
                .foregroundStyle(Palette.secondaryInk)
                .lineStyle(style)
                .accessibilityHidden(true)
            RuleMark(x: .value("Date", pair.outlineEnd), yStart: .value("So far", bottom),
                     yEnd: .value("So far", top))
                .foregroundStyle(Palette.secondaryInk)
                .lineStyle(style)
                .accessibilityHidden(true)
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
                    PlanMoneyInOutCallout(money: money, period: period)
                }
        }
    }

    private func summary(_ pairs: [Pair]) -> ChartSummary {
        let locale = self.locale
        func spoken(_ value: (MoneyInOutPeriod) -> Decimal) -> [(String, Double)] {
            pairs.map { (AmountFormat.mediumDate($0.period.through, locale: locale), value($0.period).doubleValue) }
        }
        let unit = money.grain == .months ? "month" : "year"
        return ChartSummary(
            title: "Money in and out",
            summary: "What came in, what went into your pension, the tax and what was spent, each \(unit).",
            xTitle: "Date", yTitle: "Amount",
            series: [
                ChartSummary.Series(name: "Came in", points: spoken(\.moneyIn)),
                ChartSummary.Series(name: "Pension", points: spoken(\.pensionContributions)),
                ChartSummary.Series(name: "Tax", points: spoken(\.tax)),
                ChartSummary.Series(name: "Spent", points: spoken(\.spent)),
            ],
            describeValue: ChartStyle.spokenAmount(currency: money.currency, hidden: hidesAmounts))
    }
}

/// The key of *Money in and out*: came in, pension, spent and tax; the
/// hatching when a period covers more than itself; and a note when a value
/// is cut at the edge.
struct PlanMoneyInOutLegend: View {
    let money: PlanMoneyInOut
    /// Whether a value is beyond the value axis
    /// (``PlanMoneyInOut/cutsAmounts(planSpending:)``).
    var cuts = false

    /// The bars' parts: came in, pension, spent and tax. *Year by year* has
    /// them alone.
    static var parts: [ChartLegendItem] {
        [
            ChartLegendItem(name: "Came in", swatch: .bar(PlanMoneyInOutChart.cameInColor)),
            ChartLegendItem(name: "Pension",
                            swatch: .fadedBar(PlanMoneyInOutChart.cameInColor,
                                              opacity: PlanMoneyInOutChart.lighterOpacity)),
            ChartLegendItem(name: "Spent",
                            swatch: .fadedBar(PlanMoneyInOutChart.spentColor,
                                              opacity: PlanMoneyInOutChart.lighterOpacity)),
            ChartLegendItem(name: "Tax", swatch: .bar(PlanMoneyInOutChart.spentColor)),
        ]
    }

    var body: some View {
        var items = Self.parts
        if money.hasCoversMore {
            items.append(ChartLegendItem(name: money.grain == .months ? "More than a month" : "More than a year",
                                         swatch: .hatchedBar(.neutral)))
        }
        return ChartLegendRow(items: items, note: cuts ? "Cut at the edge" : nil)
    }
}

/// What a period of *Money in and out* reads where the pointer or a finger
/// is (UI.md, "So far"): its last day, with "so far" or what it covers,
/// then its rows: "Came in 5.240 €", "Pension 520 €", "Tax −4.310 €",
/// "Spent −3.000 €", then what that left over, "Left over −1.550 €"; one-offs
/// it didn't count; and its savings rate, "−107%", and the rate over 12
/// months. Rates stay with the eye; amounts hide.
struct PlanMoneyInOutCallout: View {
    let money: PlanMoneyInOut
    let period: MoneyInOutPeriod

    @Environment(\.locale) private var locale

    var body: some View {
        ChartCallout {
            ChartCalloutDate(period.through.dateValue, detail: money.calloutDetail(period, locale: locale))
            if let pay = period.pay {
                ChartCalloutRow("Came in", swatch: PlanMoneyInOutChart.color(.moneyIn),
                                amount: pay.moneyIn.doubleValue, currency: money.currency)
                if pay.pension != 0 {
                    ChartCalloutRow("Pension", swatch: PlanMoneyInOutChart.color(.pension),
                                    amount: pay.pension.doubleValue, currency: money.currency)
                }
                if pay.tax != 0 {
                    ChartCalloutRow("Tax", swatch: PlanMoneyInOutChart.color(.tax),
                                    amount: (-pay.tax).doubleValue, currency: money.currency)
                }
                ChartCalloutRow("Spent", swatch: PlanMoneyInOutChart.color(.spent),
                                amount: (-pay.spent).doubleValue, currency: money.currency)
                Divider()
                ChartCalloutRow("Left over", amount: pay.saved.doubleValue, currency: money.currency)
                if period.oneOffs != 0 {
                    ChartCalloutRow("Not counted: one-offs", amount: period.oneOffs.doubleValue,
                                    currency: money.currency)
                }
                if let rate = period.rate {
                    rateRow("Savings rate", rate)
                }
                if let lastTwelveMonths = period.lastTwelveMonths?.rate {
                    rateRow("Rate over 12 months", lastTwelveMonths)
                }
            } else {
                Text("No money in and out recorded")
                    .font(.caption2)
                    .foregroundStyle(Palette.secondaryInk)
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
            PlanMoneyInOutLegend(money: money, cuts: money.cutsAmounts(planSpending: nil))
            PlanMoneyInOutChart(money: money)
        }
        Card("Amounts hidden") {
            PlanMoneyInOutChart(money: money)
                .redacted(reason: .privacy)
        }
    }
    .padding()
    .background(Palette.page)
    .previewEnvironment()
}
