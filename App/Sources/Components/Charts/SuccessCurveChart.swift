import Charts
import SwiftUI

/// Chance of success by retirement age (UI.md, "Chance of success by
/// retirement age"): one line per plan, a dotted rule at the confidence
/// level, and the earliest age where they cross, marked and labelled.
///
/// - Steps caused by pension eligibility show as steps: the line is drawn
///   straight between ages, never smoothed.
/// - Drag or tap to select an age (bind `selectedAge` to use it for the
///   other charts).
/// - With two series (comparing plans), each is labelled at its last point.
struct SuccessCurveChart: View {
    var series: [SuccessSeries]
    /// The confidence level, e.g. 0.9.
    var threshold: Double
    /// The age to mark, e.g. the earliest age reaching the threshold. By
    /// default the first series' first age at or above it.
    var highlightedAge: Int?
    var height: CGFloat = 200
    @Binding var selectedAge: Int?

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

    private var crossing: SuccessPoint? {
        guard let first = series.first else { return nil }
        if let highlightedAge { return first.points.first { $0.age == highlightedAge } }
        return first.points.first { $0.success >= threshold }
    }

    var body: some View {
        if series.allSatisfy(\.points.isEmpty) {
            ChartPlaceholder(text: "The chance of success by age appears here once the plan has run.", height: height)
        } else {
            chart
                .frame(height: height)
                .accessibilityChartDescriptor(summary)
        }
    }

    private var chart: some View {
        Chart {
            RuleMark(y: .value("Confidence", threshold))
                .foregroundStyle(Palette.mutedInk)
                .lineStyle(StrokeStyle(lineWidth: 1, dash: [1, 3]))
                .annotation(position: .top, alignment: .leading, spacing: 2) {
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
                if series.count > 1, let last = line.points.last {
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
                    .annotation(position: .top, spacing: 6) {
                        Text("\(crossing.age)")
                            .font(.caption.weight(.semibold))
                            .foregroundStyle(Palette.ink)
                    }
            }

            if let selectedAge, let point = series.first?.points.first(where: { $0.age == selectedAge }) {
                RuleMark(x: .value("Retirement age", selectedAge))
                    .foregroundStyle(Palette.axis)
                    .lineStyle(StrokeStyle(lineWidth: 1))
                    .annotation(position: .top, spacing: 4,
                                overflowResolution: .init(x: .fit(to: .chart), y: .disabled)) {
                        Text("At \(selectedAge): \(AmountFormat.percent(point.success, digits: 0))")
                            .font(.caption2.weight(.semibold))
                            .padding(Metrics.xs)
                            .background(Palette.card, in: RoundedRectangle(cornerRadius: 6, style: .continuous))
                    }
            }
        }
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
        .chartXAxis {
            AxisMarks(values: .stride(by: 5)) { value in
                AxisTick(stroke: StrokeStyle(lineWidth: 0.5)).foregroundStyle(Palette.axis)
                AxisValueLabel {
                    if let age = value.as(Int.self) {
                        Text("\(age)").font(.caption2).foregroundStyle(Palette.mutedInk)
                    }
                }
            }
        }
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
                                  points: results.successByAge.map { SuccessPoint(age: $0.age + 1, success: $0.success) }),
                ],
                threshold: results.headline.confidence)
        }
    }
}
