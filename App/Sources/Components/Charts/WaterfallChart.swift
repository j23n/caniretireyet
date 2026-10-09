import Charts
import Model
import SwiftUI
import Tracker

/// The change from one total to the next (UI.md, "Since last check-in"):
/// a headline, "▲ +5.730 € since 31 Aug", the totals before and after in
/// words, and one bar per part of the change (markets, new money, other)
/// from a shared zero line, all to the same scale (``ChangeBars``).
///
/// It used to be a waterfall, whose bars from zero made the totals huge
/// grey blocks and the changes slivers on top; the name stayed.
///
/// - Gains go right in the positive colour, losses left in the negative
///   one; each bar's signed amount is in a column of its own, in ink, so
///   no label sits on a bar and colour is never the only cue.
/// - While amounts are hidden the headline shows the change in per cent,
///   the bars keep their proportions and the amounts hide.
///
///     WaterfallChart(change: report.total, from: "31 Aug", to: "30 Sep")
struct WaterfallChart: View {
    /// Tracker's split of the change: markets, new money and other.
    var change: ValueChange
    /// The dates of the totals before and after: "31 Aug", "30 Sep".
    var from: String
    var to: String
    /// Whether the change leads, "▲ +5.730 € since 31 Aug", over the totals
    /// before and after; off where the screen says it already (the Overview).
    var showsChange = true

    @Environment(\.hidesAmounts) private var hidesAmounts
    @Environment(\.baseCurrency) private var baseCurrency
    @Environment(\.locale) private var locale

    /// The bars' thickness (thin marks: at most 24 points).
    private static let barHeight: CGFloat = 14

    var body: some View {
        let bars = ChangeBars(change)
        VStack(alignment: .leading, spacing: Metrics.m) {
            headline(bars)
            Grid(alignment: .leading, horizontalSpacing: Metrics.m, verticalSpacing: Metrics.s) {
                ForEach(bars.bars) { bar in
                    // No modifiers on the row itself: they'd turn it into one cell.
                    GridRow {
                        Text(bar.label)
                            .font(.subheadline)
                            .foregroundStyle(Palette.secondaryInk)
                            .lineLimit(1)
                            .fixedSize()
                            .accessibilityLabel(Text(verbatim: "\(bar.label), \(spokenAmount(bar.value))"))
                        ChangeBarTrack(bar: bar, zero: bars.zero)
                            .frame(height: Self.barHeight)
                            .frame(maxWidth: .infinity)
                        Text(verbatim: amountText(bar.value))
                            .font(.subheadline)
                            .monospacedDigit()
                            .foregroundStyle(Palette.ink)
                            .privacySensitive()
                            .gridColumnAlignment(.trailing)
                            .accessibilityHidden(true)
                    }
                }
            }
        }
        .accessibilityChartDescriptor(summary(bars))
    }

    @ViewBuilder
    private func headline(_ bars: ChangeBars) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            if showsChange {
                changeLine(bars)
            }
            HStack(spacing: Metrics.xs) {
                AmountText(Decimal(wholeNumber: bars.start))
                Text(verbatim: "→")
                    .accessibilityLabel("to")
                AmountText(Decimal(wholeNumber: bars.end))
            }
            .font(.subheadline)
            .foregroundStyle(Palette.secondaryInk)
        }
    }

    /// "▲ +5.730 € since 31 Aug".
    private func changeLine(_ bars: ChangeBars) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: Metrics.xs) {
            if hidesAmounts, let relative = bars.relativeChange {
                DeltaText(percent: relative)
            } else {
                DeltaText(Decimal(wholeNumber: bars.change))
            }
            Text("since \(from)")
                .foregroundStyle(Palette.secondaryInk)
        }
        .font(.title3.weight(.semibold))
    }

    private func amountText(_ value: Double) -> String {
        hidesAmounts ? AmountFormat.hidden : signed(value)
    }

    private func spokenAmount(_ value: Double) -> String {
        hidesAmounts ? (value > 0.5 ? "up" : value < -0.5 ? "down" : "unchanged") + ", amount hidden" : signed(value)
    }

    private func signed(_ value: Double) -> String {
        AmountFormat.signedAmount(Decimal(wholeNumber: value), currency: baseCurrency, locale: locale)
    }

    /// "31 Aug 312.480 €, Markets −8.950 €, …, 30 Sep 304.790 €.", the
    /// names alone while amounts are hidden.
    private func summary(_ bars: ChangeBars) -> ChartSummary {
        let currency = baseCurrency
        func total(_ name: String, _ value: Double) -> String {
            hidesAmounts ? name : "\(name) \(AmountFormat.amount(Decimal(wholeNumber: value), currency: currency))"
        }
        let parts = bars.bars.map { bar in
            hidesAmounts ? bar.label
                : "\(bar.label) \(AmountFormat.signedAmount(Decimal(wholeNumber: bar.value), currency: currency))"
        }
        let words = [total(from, bars.start)] + parts + [total(to, bars.end)]
        return ChartSummary(
            title: "Change", summary: words.joined(separator: ", ") + ".", xTitle: "Part", yTitle: "Amount",
            series: [ChartSummary.Series(name: "Change", points: bars.bars.map { ($0.label, $0.value) })],
            describeValue: ChartStyle.spokenAmount(currency: currency, hidden: hidesAmounts))
    }
}

/// One bar on its track: from the shared zero line, right for a gain in the
/// positive colour, left for a loss in the negative one, rounded at its
/// data end and square at zero.
private struct ChangeBarTrack: View {
    let bar: ChangeBars.Bar
    let zero: Double

    var body: some View {
        GeometryReader { proxy in
            let width = proxy.size.width
            let length = max(bar.direction == 0 ? 0 : 2, (bar.to - bar.from) * width)
            let start = bar.direction < 0 ? zero * width - length : zero * width
            ZStack(alignment: .leading) {
                if bar.direction != 0 {
                    UnevenRoundedRectangle(
                        topLeadingRadius: bar.direction < 0 ? Metrics.barRadius : 0,
                        bottomLeadingRadius: bar.direction < 0 ? Metrics.barRadius : 0,
                        bottomTrailingRadius: bar.direction > 0 ? Metrics.barRadius : 0,
                        topTrailingRadius: bar.direction > 0 ? Metrics.barRadius : 0,
                        style: .continuous)
                        .fill(bar.direction > 0 ? Palette.positive : Palette.negative)
                        .frame(width: length)
                        .offset(x: start)
                }
                Rectangle()
                    .fill(Palette.axis)
                    .frame(width: 1)
                    .offset(x: min(max(zero * width - 0.5, 0), max(width - 1, 0)))
            }
            .frame(width: width, height: proxy.size.height, alignment: .leading)
        }
        .accessibilityHidden(true)
    }
}

#Preview("Since last check-in") {
    let change = PreviewLibrary.valuator.changeSinceLastCheckIn(asOf: PreviewLibrary.latestCheckIn)?.total ?? .zero
    ScrollView {
        VStack(spacing: Metrics.l) {
            Card("Since last check-in") {
                WaterfallChart(change: change, from: "31 Aug", to: "30 Sep")
            }
            Card("A loss, made up") {
                WaterfallChart(change: ValueChange(start: 312_480, market: -8_950, newMoney: 1_500, other: -240,
                                                   end: 304_790),
                               from: "31 Aug", to: "30 Sep")
            }
            Card("Amounts hidden") {
                WaterfallChart(change: change, from: "31 Aug", to: "30 Sep")
                    .environment(\.hidesAmounts, true)
            }
        }
        .padding()
    }
    .background(Palette.page)
}
