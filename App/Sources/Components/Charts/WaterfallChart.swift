import Charts
import Model
import SwiftUI
import Tracker

/// A small waterfall from one total to another through the changes between
/// them (UI.md, "Since last check-in"): markets, new money and other. Each
/// change is labelled with its sign and arrow; totals with their amount.
///
///     WaterfallChart(steps: WaterfallStep.steps(for: report.total))
struct WaterfallChart: View {
    var steps: [WaterfallStep]
    /// `nil` for the base currency.
    var currency: CurrencyCode?
    var height: CGFloat = 180

    @Environment(\.hidesAmounts) private var hidesAmounts
    @Environment(\.baseCurrency) private var baseCurrency

    /// One floating bar per step.
    struct Bar: Identifiable {
        var step: WaterfallStep
        var start: Double
        var end: Double
        var id: String { step.id }
    }

    /// The bars: totals from zero, changes from the running total.
    var bars: [Bar] {
        var running = 0.0
        return steps.map { step in
            switch step.kind {
            case .total:
                running = step.value
                return Bar(step: step, start: 0, end: step.value)
            case .change:
                defer { running += step.value }
                return Bar(step: step, start: running, end: running + step.value)
            }
        }
    }

    var body: some View {
        if steps.isEmpty {
            ChartPlaceholder(text: "The change since the last check-in appears after the second one.", height: height)
        } else {
            chart
                .frame(height: height)
                .accessibilityChartDescriptor(summary)
        }
    }

    private var chart: some View {
        Chart {
            ForEach(bars) { bar in
                BarMark(x: .value("Step", bar.step.label), yStart: .value("From", bar.start),
                        yEnd: .value("To", bar.end), width: .ratio(0.55))
                    .foregroundStyle(bar.step.kind == .total ? Palette.mutedInk.opacity(0.45) : Palette.accent)
                    .cornerRadius(Metrics.barRadius)
                    .annotation(position: bar.end >= bar.start ? .top : .bottom, spacing: 2) {
                        label(for: bar.step)
                    }
            }
        }
        .chartYScale(domain: .automatic(includesZero: false))
        .chartYAxis(.hidden)
        .chartXAxis {
            AxisMarks { _ in
                AxisValueLabel().font(.caption2).foregroundStyle(Palette.secondaryInk)
            }
        }
    }

    @ViewBuilder
    private func label(for step: WaterfallStep) -> some View {
        let amount = Decimal(Int(step.value.rounded()))
        switch step.kind {
        case .total:
            AmountText(amount, currency: currency).font(.caption2.weight(.semibold))
        case .change:
            DeltaText(amount, currency: currency, showsArrow: false).font(.caption2)
        }
    }

    private var summary: ChartSummary {
        let resolved = currency ?? baseCurrency
        let parts = steps.map { step in
            hidesAmounts ? step.label
                : "\(step.label) \(step.kind == .total ? AmountFormat.amount(Decimal(Int(step.value.rounded())), currency: resolved) : AmountFormat.signedAmount(Decimal(Int(step.value.rounded())), currency: resolved))"
        }
        return ChartSummary(
            title: "Change", summary: parts.joined(separator: ", ") + ".", xTitle: "Step", yTitle: "Amount",
            series: [ChartSummary.Series(name: "Change", points: steps.map { ($0.label, $0.value) })],
            describeValue: ChartStyle.spokenAmount(currency: resolved))
    }
}

#Preview("Waterfall") {
    let change = PreviewLibrary.valuator.changeSinceLastCheckIn(asOf: PreviewLibrary.latestCheckIn)
    ScrollView {
        Card("Since last check-in") {
            WaterfallChart(steps: change.map { WaterfallStep.steps(for: $0.total, startLabel: "31 Aug", endLabel: "30 Sep") }
                ?? [])
        }
        .padding()
    }
    .background(Palette.page)
}
