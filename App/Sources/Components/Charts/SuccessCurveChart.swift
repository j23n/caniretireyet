import Charts
import SwiftUI

/// Chance of success by retirement age (UI.md, "Chance of success by
/// retirement age"): the chance as one line in the accent, a dotted rule at
/// the confidence level, and the earliest age where they cross, marked and
/// labelled.
///
/// - The age axis fits the curve: from the first age simulated (today's)
///   to the last, with a tick every 5 years (or 2, or 10, as the width
///   allows), never a label per age.
/// - Steps caused by pension eligibility show as steps: the line is drawn
///   straight between ages, never smoothed.
/// - Drag or tap to select an age (bind `selectedAge` to use it for the
///   other charts). The callout stays inside the chart.
struct SuccessCurveChart: View {
    var points: [SuccessPoint]
    /// The confidence level, e.g. 0.9.
    var threshold: Double
    /// The age to mark, e.g. the earliest age reaching the threshold. By
    /// default the first age at or above it.
    var highlightedAge: Int?
    @Binding var selectedAge: Int?
    @State private var width: CGFloat = ChartStyle.defaultWidth

    private static let height: CGFloat = 200

    init(points: [SuccessPoint], threshold: Double, highlightedAge: Int? = nil,
         selectedAge: Binding<Int?> = .constant(nil)) {
        self.points = points
        self.threshold = threshold
        self.highlightedAge = highlightedAge
        _selectedAge = selectedAge
    }

    private var crossing: SuccessPoint? {
        if let highlightedAge { return points.first { $0.age == highlightedAge } }
        return points.first { $0.success >= threshold }
    }

    var body: some View {
        if points.isEmpty {
            ChartPlaceholder(text: "The chance of success by age appears here once the plan has run.",
                             height: Self.height)
        } else {
            chart
                .frame(height: Self.height)
                .measuringWidth($width)
                .accessibilityChartDescriptor(summary)
        }
    }

    /// The ages shown, from the curve's first to its last, and the ticks
    /// that fit the chart's width.
    private var ages: (domain: ClosedRange<Int>, ticks: [Int]) {
        let first = points.map(\.age).min() ?? 0
        let last = max(points.map(\.age).max() ?? first, first + 1)
        let plotWidth = ChartText.plotWidth(chartWidth: Double(width))
        return (first...last, IntegerTicks.values(in: first...last, plotWidth: plotWidth,
                                                  spacing: IntegerTicks.ageSpacing, steps: [1, 2, 5, 10]))
    }

    /// Whether the curve ends above the confidence level: its label then
    /// goes under the rule, where the curve isn't.
    private var endsAbove: Bool {
        (points.max { $0.age < $1.age }?.success ?? 0) >= threshold
    }

    private var chart: some View {
        let ages = self.ages
        return Chart {
            RuleMark(y: .value("Confidence", threshold))
                .foregroundStyle(Palette.mutedInk)
                .lineStyle(StrokeStyle(lineWidth: 1, dash: [1, 3]))
                .annotation(position: endsAbove ? .bottom : .top, alignment: .trailing, spacing: 2) {
                    Text("\(AmountFormat.percent(threshold, digits: 0)) confidence")
                        .font(.caption2)
                        .foregroundStyle(Palette.secondaryInk)
                }

            ForEach(points) { point in
                LineMark(x: .value("Retirement age", point.age), y: .value("Chance of success", point.success),
                         series: .value("Plan", "Chance of success"))
                    .foregroundStyle(Palette.accent)
                    .lineStyle(StrokeStyle(lineWidth: Metrics.lineWidth, lineCap: .round, lineJoin: .round))
            }

            if let crossing {
                PointMark(x: .value("Retirement age", crossing.age), y: .value("Chance of success", crossing.success))
                    .foregroundStyle(Palette.accent)
                    .symbolSize(90)
                    .annotation(position: .top, spacing: 6,
                                overflowResolution: .init(x: .fit(to: .chart), y: .fit(to: .chart))) {
                        Text("\(crossing.age)")
                            .font(.caption.weight(.semibold))
                            .foregroundStyle(Palette.ink)
                    }
            }

            if let selectedAge, let point = points.first(where: { $0.age == selectedAge }) {
                RuleMark(x: .value("Retirement age", selectedAge))
                    .foregroundStyle(Palette.secondaryInk)
                    .lineStyle(StrokeStyle(lineWidth: 1))
                    .annotation(position: .top, spacing: 4,
                                overflowResolution: .init(x: .fit(to: .chart), y: .fit(to: .chart))) {
                        Text("At \(selectedAge): \(AmountFormat.percent(point.success, digits: 0))")
                            .font(.caption2.weight(.semibold))
                            .padding(Metrics.xs)
                            .background(Palette.card, in: RoundedRectangle(cornerRadius: 6, style: .continuous))
                            .overlay {
                                RoundedRectangle(cornerRadius: 6, style: .continuous).strokeBorder(Palette.border)
                            }
                    }
            }
        }
        .chartXScale(domain: ages.domain)
        .chartYScale(domain: 0...1)
        .chartXSelection(value: $selectedAge)
        .chartYAxis {
            AxisMarks(position: .leading, values: [0, 0.5, 1]) { value in
                AxisGridLine(stroke: StrokeStyle(lineWidth: 0.5)).foregroundStyle(Palette.gridline)
                AxisValueLabel {
                    if let share = value.as(Double.self) {
                        Text(AmountFormat.percent(share, digits: 0)).font(.caption2).foregroundStyle(Palette.mutedInk)
                    }
                }
            }
        }
        .chartXAxis { tickAxis(ages.ticks) { (age: Int) in String(age) } }
        .chartLegend(.hidden)
    }

    private var summary: ChartSummary {
        var text = "Chance of success by retirement age, against a \(AmountFormat.percent(threshold, digits: 0)) confidence level."
        if let crossing {
            text += " It reaches the level at \(crossing.age)."
        } else {
            text += " No age reaches it."
        }
        return ChartSummary(
            title: "Chance of success by retirement age", summary: text, xTitle: "Retirement age",
            yTitle: "Chance of success",
            series: [ChartSummary.Series(name: "Chance of success",
                                         points: points.map { ("\($0.age)", $0.success) })],
            describeValue: ChartStyle.spokenShare)
    }
}

#Preview("Success curve") {
    PreviewResultsView { results in
        Card("Chance of success by retirement age") {
            SuccessCurveChart(points: results.successByAge, threshold: results.headline.confidence)
        }
    }
}
