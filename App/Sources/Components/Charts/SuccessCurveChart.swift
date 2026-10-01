import Charts
import SwiftUI

/// Chance of success by retirement age (UI.md, "Chance of success by
/// retirement age"): one line per plan, a dotted rule at the confidence
/// level, and the earliest age where they cross, marked and labelled.
///
/// - The age axis fits the curve: from the first age simulated (today's)
///   to the last, with a tick every 5 years (or 2, or 10, as the width
///   allows), never a label per age.
/// - Steps caused by pension eligibility show as steps: the line is drawn
///   straight between ages, never smoothed.
/// - Drag or tap to select an age (bind `selectedAge` to use it for the
///   other charts). The callout stays inside the chart.
/// - With two series (comparing plans), a legend sits in its own row
///   above, and each line is labelled at its end when the ends are apart.
struct SuccessCurveChart: View {
    var series: [SuccessSeries]
    /// The confidence level, e.g. 0.9.
    var threshold: Double
    /// The age to mark, e.g. the earliest age reaching the threshold. By
    /// default the first series' first age at or above it.
    var highlightedAge: Int?
    var height: CGFloat = 200
    @Binding var selectedAge: Int?
    @State private var width: CGFloat = ChartStyle.defaultWidth

    /// One plan's curve.
    init(points: [SuccessPoint], threshold: Double, highlightedAge: Int? = nil, height: CGFloat = 200,
         selectedAge: Binding<Int?> = .constant(nil)) {
        self.init(series: [SuccessSeries(id: "plan", name: "Chance of success", color: .accent, points: points)],
                  threshold: threshold, highlightedAge: highlightedAge, height: height, selectedAge: selectedAge)
    }

    /// Several plans' curves, overlaid.
    init(series: [SuccessSeries], threshold: Double, highlightedAge: Int? = nil, height: CGFloat = 200,
         selectedAge: Binding<Int?> = .constant(nil)) {
        self.series = series
        self.threshold = threshold
        self.highlightedAge = highlightedAge
        self.height = height
        _selectedAge = selectedAge
    }

    private struct Layout {
        var domain: ClosedRange<Int>
        var ticks: [Int]
        /// Whether each line is labelled at its end.
        var labelsEnds: Bool
    }

    private var crossing: SuccessPoint? {
        guard let first = series.first else { return nil }
        if let highlightedAge { return first.points.first { $0.age == highlightedAge } }
        return first.points.first { $0.success >= threshold }
    }

    var body: some View {
        if series.allSatisfy(\.points.isEmpty) {
            ChartPlaceholder(text: "The chance of success by age appears here once the plan has run.", height: height)
        } else {
            VStack(alignment: .leading, spacing: Metrics.s) {
                if series.count > 1 {
                    ChartLegendRow(items: series.map {
                        ChartLegendItem(name: $0.name, swatch: .line($0.color, dashed: false))
                    })
                }
                chart(layout)
                    .frame(height: height)
                    .measuringWidth($width)
                    .accessibilityChartDescriptor(summary)
            }
        }
    }

    private var layout: Layout {
        let ages = series.flatMap { $0.points.map(\.age) }
        let first = ages.min() ?? 0
        let last = max(ages.max() ?? first, first + 1)
        let plotWidth = ChartText.plotWidth(chartWidth: Double(width))
        let ends = series.compactMap { $0.points.max { $0.age < $1.age }?.success }
        let apart = ends.count > 1 && zip(ends, ends.dropFirst()).allSatisfy { abs($0 - $1) >= 0.12 }
        let labelWidth = (series.map { ChartText.width(of: $0.name) }.max() ?? 0) + 12
        let padding = apart
            ? endLabelPadding(span: Double(last - first), labelWidth: labelWidth, plotWidth: plotWidth) : 0
        let extra = Int(padding.rounded(.up))
        let dataWidth = plotWidth * Double(last - first) / Double(last - first + extra)
        return Layout(domain: first...(last + extra),
                      ticks: IntegerTicks.values(in: first...last, plotWidth: dataWidth,
                                                 spacing: IntegerTicks.ageSpacing, steps: [1, 2, 5, 10]),
                      labelsEnds: apart)
    }

    /// Whether the first curve ends above the confidence level: its label
    /// then goes under the rule, where the curve isn't.
    private var endsAbove: Bool {
        (series.first?.points.max { $0.age < $1.age }?.success ?? 0) >= threshold
    }

    private func chart(_ layout: Layout) -> some View {
        Chart {
            RuleMark(y: .value("Confidence", threshold))
                .foregroundStyle(Palette.mutedInk)
                .lineStyle(StrokeStyle(lineWidth: 1, dash: [1, 3]))
                .annotation(position: endsAbove ? .bottom : .top, alignment: .trailing, spacing: 2) {
                    Text("\(AmountFormat.percent(threshold, digits: 0)) confidence")
                        .font(.caption2)
                        .foregroundStyle(Palette.secondaryInk)
                }

            ForEach(series) { line in
                ForEach(line.points) { point in
                    LineMark(x: .value("Retirement age", point.age), y: .value("Chance of success", point.success),
                             series: .value("Plan", line.name))
                        .foregroundStyle(Palette.color(for: line.color))
                        .lineStyle(StrokeStyle(lineWidth: Metrics.lineWidth, lineCap: .round, lineJoin: .round))
                }
                if layout.labelsEnds, let last = line.points.max(by: { $0.age < $1.age }) {
                    PointMark(x: .value("Retirement age", last.age), y: .value("Chance of success", last.success))
                        .foregroundStyle(Palette.color(for: line.color))
                        .symbolSize(30)
                        .annotation(position: .trailing, spacing: 4) {
                            Text(line.name).font(.caption2).foregroundStyle(Palette.secondaryInk)
                        }
                }
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

            if let selectedAge, let point = series.first?.points.first(where: { $0.age == selectedAge }) {
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
        .chartXScale(domain: layout.domain)
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
        .chartXAxis { ageAxis(layout.ticks) }
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
            series: series.map { line in
                ChartSummary.Series(name: line.name, points: line.points.map { ("\($0.age)", $0.success) })
            },
            describeValue: ChartStyle.spokenShare)
    }
}

#Preview("Success curve") {
    PreviewResultsView { results in
        Card("Chance of success by retirement age") {
            SuccessCurveChart(points: results.successByAge, threshold: results.headline.confidence)
        }
        Card("Two plans") {
            SuccessCurveChart(
                series: [
                    SuccessSeries(id: "a", name: "Forfettario", color: .series(0), points: results.successByAge),
                    SuccessSeries(id: "b", name: "Ordinario", color: .series(1),
                                  points: results.successByAge.map {
                                      SuccessPoint(age: $0.age + 1, success: $0.success * 0.8)
                                  }),
                ],
                threshold: results.headline.confidence)
        }
    }
}
