import Charts
import Model
import SwiftUI
import Tracker

/// So far's *Money in and out* (UI.md, "So far"): per month, what came in
/// as one bar from zero (``PayStack``), split into what was saved, with
/// the part paid into pensions lighter at its bottom, what was spent and
/// the tax; and a green mark at what came in before tax. A part below zero
/// (a month whose tax bill took more than it saved) hangs below the zero
/// line. In the base currency at each value's date. A period whose values
/// cover more than it, after a skipped check-in, has a hatched bar, and its
/// callout says what it covers. The current month is drawn lighter ("so
/// far"). The value axis fits what's typical around each period
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

    /// Saved: the accent, the pension part of it lighter; spent: orange,
    /// lighter; tax: orange; what came in: green.
    static let savedColor = ChartColor.accent
    static let spentColor = ChartColor.series(1)
    static let taxColor = ChartColor.series(1)
    static let cameInColor = ChartColor.series(5)
    /// How much of their colour the pension part and what was spent keep.
    static let pensionOpacity = 0.45
    static let spentOpacity = 0.5

    /// A part's colour.
    static func color(_ part: PayStack.Part) -> Color {
        switch part {
        case .pension: Palette.color(for: savedColor).opacity(pensionOpacity)
        case .saved: Palette.color(for: savedColor)
        case .spent: Palette.color(for: spentColor).opacity(spentOpacity)
        case .tax: Palette.color(for: taxColor)
        }
    }

    /// A part's name, as the legend and the callout say it.
    static func name(_ part: PayStack.Part) -> String {
        switch part {
        case .pension: "Into your pension"
        case .saved: "Saved"
        case .spent: "Spent"
        case .tax: "Tax"
        }
    }

    private var hidesAmounts: Bool { redactionReasons.hidesAmounts }

    /// One period's bar and its came-in mark.
    private struct Bar: Identifiable {
        var period: MoneyInOutPeriod
        var stack: PayStack
        var start: Date
        var end: Date
        var markStart: Date
        var markEnd: Date
        var middle: Date
        var isSoFar: Bool
        var coversMore: Bool

        var id: Date { middle }
        /// Keeps the bar's areas apart from the others'.
        var key: String { period.from.description }
    }

    private var bars: [Bar] {
        money.counted.compactMap { period in
            guard let stack = period.stack else { return nil }
            let span = money.timeSpan(of: period)
            return Bar(period: period, stack: stack, start: PlanMoneyInOut.date(0.16, across: span),
                       end: PlanMoneyInOut.date(0.84, across: span),
                       markStart: PlanMoneyInOut.date(0.08, across: span),
                       markEnd: PlanMoneyInOut.date(0.92, across: span), middle: money.middle(of: period),
                       isSoFar: money.isSoFar(period), coversMore: money.coversMore(period))
        }
    }

    var body: some View {
        let bars = self.bars
        let scale = money.amountScale(planSpending: nil)
        let domain = money.domain ?? (Date.now...Date.now.addingTimeInterval(31 * 86_400))
        chart(bars, scale: scale, domain: domain)
            .frame(height: Self.height)
            .measuringWidth($width)
            .accessibilityChartDescriptor(summary(bars))
            .privacySensitiveInFeedback()
    }

    /// How much of its colour the "so far" period keeps.
    private static let soFarOpacity = 0.45

    /// A part's fill: its colour, hatched when its period covers more, and
    /// lighter while it's so far.
    private static func fill(_ part: PayStack.Part, of bar: Bar) -> AnyShapeStyle {
        let color = Self.color(part).opacity(bar.isSoFar ? soFarOpacity : 1)
        if bar.coversMore {
            return AnyShapeStyle(ChartHatch.style(color))
        }
        return AnyShapeStyle(color)
    }

    /// The period nearest the pointer or a finger.
    private var selectedPeriod: MoneyInOutPeriod? {
        guard let selectedDate else { return nil }
        return money.period(nearest: selectedDate)
    }

    private func chart(_ bars: [Bar], scale: AmountScale, domain: ClosedRange<Date>) -> some View {
        let ticks = TimeTicks(domain: domain, plotWidth: max(Double(width) - 48, 1))
        let base: Double? = money.relativeBase
        return Chart {
            stacks(bars, within: scale.domain)
            zeroRule()
            cameInMarks(bars, within: scale.domain)
            selectionRule(selectedPeriod)
        }
        .chartLegend(.hidden)
        .chartXSelection(value: $selectedDate)
        .chartXScale(domain: domain)
        .chartYScale(domain: scale.domain)
        .chartYAxis { amountAxis(hidesAmounts: hidesAmounts, scale: scale, relativeTo: base) }
        .chartXAxis { dateAxis(ticks) }
    }

    /// Each period's bar: each part an area between the bar's start and
    /// end, kept within the value axis's `domain`, with a gap where the bar
    /// goes beyond it; the part's name and the bar's `key` keep an area
    /// apart from the others.
    @ChartContentBuilder
    private func stacks(_ bars: [Bar], within domain: ClosedRange<Double>) -> some ChartContent {
        ForEach(bars) { bar in
            ForEach(bar.stack.segments, id: \.self) { segment in
                let low = PlanMoneyInOut.clamped(min(segment.from, segment.to).doubleValue, to: domain)
                let high = PlanMoneyInOut.clamped(max(segment.from, segment.to).doubleValue, to: domain)
                let series = Self.name(segment.part) + " " + bar.key
                AreaMark(x: .value("Date", bar.start), yStart: .value("From", low), yEnd: .value("To", high),
                         series: .value("Bar", series))
                    .foregroundStyle(Self.fill(segment.part, of: bar))
                    .spokenValue(spokenAmount(segment.length.doubleValue, within: domain))
                AreaMark(x: .value("Date", bar.end), yStart: .value("From", low), yEnd: .value("To", high),
                         series: .value("Bar", series))
                    .foregroundStyle(Self.fill(segment.part, of: bar))
                    .spokenValue(spokenAmount(segment.length.doubleValue, within: domain))
            }
            if let gap = ChartCut.gap(bar.stack.top.doubleValue, within: domain) {
                ChartCut.gapMark(from: bar.start, to: bar.end, at: gap, surface: surface)
            }
            if let gap = ChartCut.gap(bar.stack.bottom.doubleValue, within: domain) {
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

    /// What came in before tax: a green mark across each bar, at the
    /// value axis's edge when it's beyond it.
    @ChartContentBuilder
    private func cameInMarks(_ bars: [Bar], within domain: ClosedRange<Double>) -> some ChartContent {
        ForEach(bars) { bar in
            let cameIn = bar.stack.cameIn.doubleValue
            RuleMark(xStart: .value("Date", bar.markStart), xEnd: .value("Date", bar.markEnd),
                     y: .value("Came in", PlanMoneyInOut.clamped(cameIn, to: domain)))
                .foregroundStyle(Palette.stroke(for: Self.cameInColor).opacity(bar.isSoFar ? Self.soFarOpacity : 1))
                .lineStyle(StrokeStyle(lineWidth: 2, lineCap: .round))
                .spokenValue(spokenAmount(cameIn, within: domain))
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

    private func summary(_ bars: [Bar]) -> ChartSummary {
        let locale = self.locale
        func spoken(_ value: (MoneyInOutPeriod) -> Decimal) -> [(String, Double)] {
            bars.map { (AmountFormat.mediumDate($0.period.through, locale: locale), value($0.period).doubleValue) }
        }
        let unit = money.grain == .months ? "month" : "year"
        return ChartSummary(
            title: "Money in and out",
            summary: "What came in, the tax, what was spent and what you saved, each \(unit).",
            xTitle: "Date", yTitle: "Amount",
            series: [
                ChartSummary.Series(name: "Came in before tax", points: spoken(\.beforeTax)),
                ChartSummary.Series(name: "Tax", points: spoken(\.tax)),
                ChartSummary.Series(name: "Spent", points: spoken(\.spent)),
                ChartSummary.Series(name: "Saved", points: spoken(\.saved)),
            ],
            describeValue: ChartStyle.spokenAmount(currency: money.currency, hidden: hidesAmounts))
    }
}

/// The key of *Money in and out*: saved and its pension part, spent, tax
/// and what came in before tax; the hatching when a period covers more than itself;
/// and a note when a value is cut at the edge.
struct PlanMoneyInOutLegend: View {
    let money: PlanMoneyInOut
    /// Whether a value is beyond the value axis
    /// (``PlanMoneyInOut/cutsAmounts(planSpending:)``).
    var cuts = false

    /// The bar's parts: saved and its pension part, spent and tax. *Year
    /// by year* has them alone.
    static var parts: [ChartLegendItem] {
        [
            ChartLegendItem(name: "Saved", swatch: .bar(PlanMoneyInOutChart.savedColor)),
            ChartLegendItem(name: "of it into your pension",
                            swatch: .fadedBar(PlanMoneyInOutChart.savedColor,
                                              opacity: PlanMoneyInOutChart.pensionOpacity)),
            ChartLegendItem(name: "Spent",
                            swatch: .fadedBar(PlanMoneyInOutChart.spentColor,
                                              opacity: PlanMoneyInOutChart.spentOpacity)),
            ChartLegendItem(name: "Tax", swatch: .bar(PlanMoneyInOutChart.taxColor)),
        ]
    }

    var body: some View {
        var items = Self.parts
        items.append(ChartLegendItem(name: "Came in before tax",
                                     swatch: .line(PlanMoneyInOutChart.cameInColor, dashed: false)))
        if money.hasCoversMore {
            items.append(ChartLegendItem(name: money.grain == .months ? "More than a month" : "More than a year",
                                         swatch: .hatchedBar(.neutral)))
        }
        return ChartLegendRow(items: items, note: cuts ? "Cut at the edge" : nil)
    }
}

/// What a period of *Money in and out* reads where the pointer or a finger
/// is (UI.md, "So far"): its last day, with "so far" or what it covers,
/// then its pay as Today's *Your pay* tile has it: "Came in 5.240 €", "Into
/// your pension 520 €", "Tax −4.310 €", "Spent −3.000 €", then "You saved
/// −1.550 €"; one-offs it didn't count; and its savings rate, "−107%", and
/// the rate over 12 months. Rates stay with the eye; amounts hide.
struct PlanMoneyInOutCallout: View {
    let money: PlanMoneyInOut
    let period: MoneyInOutPeriod

    @Environment(\.locale) private var locale

    var body: some View {
        ChartCallout {
            ChartCalloutDate(period.through.dateValue, detail: money.calloutDetail(period, locale: locale))
            if let pay = period.pay {
                ChartCalloutRow("Came in", amount: pay.moneyIn.doubleValue, currency: money.currency)
                if pay.pension != 0 {
                    ChartCalloutRow("Into your pension", swatch: PlanMoneyInOutChart.color(.pension),
                                    amount: pay.pension.doubleValue, currency: money.currency)
                }
                if pay.tax != 0 {
                    ChartCalloutRow("Tax", swatch: PlanMoneyInOutChart.color(.tax),
                                    amount: (-pay.tax).doubleValue, currency: money.currency)
                }
                ChartCalloutRow("Spent", swatch: PlanMoneyInOutChart.color(.spent),
                                amount: (-pay.spent).doubleValue, currency: money.currency)
                Divider()
                ChartCalloutRow("You saved", swatch: PlanMoneyInOutChart.color(.saved),
                                amount: pay.saved.doubleValue, currency: money.currency)
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
